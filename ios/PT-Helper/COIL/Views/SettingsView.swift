import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import StoreKit

struct SettingsView: View {
    let userName: String
    var onEditProfile: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var consentService = ConsentService.shared
    @State private var showWithdrawConsentConfirmation = false
    @State private var showWithdrawDone = false
    @State private var showSignOutConfirmation = false
    @State private var showSignOutError = false
    @State private var signOutErrorMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var reminderDate = Date()
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false
    @State private var showConsumerHealthDataPolicy = false
    @State private var showReportConcern = false
    @State private var showSafetyResources = false
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bgGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Profile card
                        profileCard

                        // Appearance
                        appearanceCard

                        // Notifications
                        notificationsCard

                        // Debug & Feedback
                        debugFeedbackCard

                        // Help & Support (audit #84)
                        helpSupportCard

                        // Legal
                        legalCard

                        // Actions
                        actionsCard

                        // Danger zone
                        dangerZoneCard

                        // App version
                        Text(appVersionText)
                            .font(AppFonts.micro)
                            .foregroundColor(Color.white.opacity(0.5))
                            .padding(.top, AppSpacing.lg)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                    .floatingTabBarClearance()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    AnalyticsService.shared.log(.signedOut)
                    SessionLogger.shared.logUserAction(.buttonTapped, action: "signOut")
                    Task {
                        // Clear the FCM token while STILL authenticated — after
                        // signOut the client can't write Firestore and the token
                        // would linger on this (possibly shared) device under the
                        // former account (P2-01).
                        await NotificationService.shared.clearFCMToken()
                        do {
                            try Auth.auth().signOut()
                        } catch {
                            SessionLogger.shared.logError(error, context: "Auth.signOut",
                                                           metadata: ["screen": "SettingsView"])
                            AnalyticsService.shared.log(.errorShown, parameters: [
                                "screen": "SettingsView",
                                "error_type": "sign_out_failed"
                            ])
                            signOutErrorMessage = error.localizedDescription
                            showSignOutError = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Couldn't sign you out", isPresented: $showSignOutError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(signOutErrorMessage)
            }
            .confirmationDialog("Delete Account", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    AnalyticsService.shared.log(.accountDeleteAttempted)
                    SessionLogger.shared.logUserAction(.buttonTapped, action: "accountDeleteAttempted")
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account, all health data, rehab plans, and workout history. This cannot be undone.")
            }
            .alert("Couldn't delete your account", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "An unknown error occurred.")
            }
            .confirmationDialog("Withdraw Health Data Consent", isPresented: $showWithdrawConsentConfirmation, titleVisibility: .visible) {
                Button("Withdraw Consent", role: .destructive) {
                    ConsentService.shared.revokeHealthDataConsent()
                    showWithdrawDone = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("COIL will stop collecting and using your health data. You'll need to consent again before starting new assessments or using health features. Your existing data is kept until you delete your account.")
            }
            .alert("Consent Withdrawn", isPresented: $showWithdrawDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("New health-data features are paused until you consent again. To erase your data entirely, use Delete Account.")
            }
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        AppColors.primaryText.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: AppSpacing.md) {
                            ProgressView()
                                .scaleEffect(1.3)
                                .tint(AppColors.ctaText)
                            Text("Deleting account...")
                                .font(AppFonts.body)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .padding(AppSpacing.xxl)
                        .background(.ultraThinMaterial)
                        .cornerRadius(AppCorners.large)
                    }
                }
            }
        }
        .trackScreen("Settings")
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentView(title: "Privacy Policy", markdownContent: LegalContent.privacyPolicy)
        }
        .sheet(isPresented: $showTermsOfService) {
            LegalDocumentView(title: "Terms of Service", markdownContent: LegalContent.termsOfService)
        }
        .sheet(isPresented: $showConsumerHealthDataPolicy) {
            LegalDocumentView(title: "Consumer Health Data Policy", markdownContent: LegalContent.consumerHealthDataPolicy)
        }
        .sheet(isPresented: $showReportConcern) {
            ReportConcernView()
        }
        .sheet(isPresented: $showSafetyResources) {
            MinorSafetyResourcesView { showSafetyResources = false }
        }
    }

    // MARK: - Account Deletion

    /// Classifies the `deleteAccount` endpoint response. Only HTTP 200 is a
    /// confirmed server-side deletion. The server authenticates *before* it
    /// deletes anything, so a 401 means the request was never authorized and
    /// nothing was deleted — retry once with a force-refreshed token, then fail.
    /// A 401 must never be treated as success: that would tell the user their
    /// health data was erased while it still lives on the server. (An idempotent
    /// retry against an already-deleted account returns 200, not 401, because the
    /// server swallows `auth/user-not-found`.)
    enum AccountDeletionOutcome: Equatable {
        case deleted
        case retryWithFreshToken
        case failed(status: Int)

        static func classify(status: Int, didRefreshToken: Bool) -> AccountDeletionOutcome {
            if status == 200 { return .deleted }
            if status == 401 && !didRefreshToken { return .retryWithFreshToken }
            return .failed(status: status)
        }
    }

    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        isDeletingAccount = true
        Task {
            do {
                try await performAccountDeletion(user: user, didRefreshToken: false)
                await MainActor.run { clearAllLocalUserData() }
                try? Auth.auth().signOut()
                await MainActor.run {
                    AnalyticsService.shared.log(.accountDeleted)
                    isDeletingAccount = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    AnalyticsService.shared.log(.accountDeleteFailed,
                        parameters: ["reason": error.localizedDescription])
                    isDeletingAccount = false
                    deleteError = error.localizedDescription
                    showDeleteError = true
                }
            }
        }
    }

    /// Calls the `deleteAccount` endpoint and succeeds ONLY on a confirmed 200.
    /// A first 401 forces a token refresh and retries exactly once; anything that
    /// isn't a 200 throws, so the caller never clears local data or claims
    /// deletion on an unconfirmed response.
    private func performAccountDeletion(user: User, didRefreshToken: Bool) async throws {
        let idToken = try await user.getIDToken(forcingRefresh: didRefreshToken)
        var request = URLRequest(url: URL(string: APIConfig.deleteAccountURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch AccountDeletionOutcome.classify(status: status, didRefreshToken: didRefreshToken) {
        case .deleted:
            return
        case .retryWithFreshToken:
            try await performAccountDeletion(user: user, didRefreshToken: true)
        case .failed(let code):
            throw NSError(domain: "DeleteAccount", code: code,
                userInfo: [NSLocalizedDescriptionKey:
                    "The server couldn't complete the deletion (code \(code)). Your account was NOT deleted — please try again."])
        }
    }

    @MainActor
    private func clearAllLocalUserData() {
        // GA4 is a processor the deletion function cannot reach, so clear the
        // local identifiers here; already-exported events need a property-side
        // deletion request.
        AnalyticsService.shared.resetForAccountDeletion()
        UserProfileService.shared.clear()
        DisclaimerManager.reset()
        OnboardingViewModel.clearDraft()
        AnalysisResultStore.shared.clear()
        SeriousWarningAcknowledgements.clearAll()
        SessionLogger.shared.clearAllLocalData()
        GuidedWorkoutViewModel.clearAllLocalWorkoutState()
        ConsentService.clearLocalMirrors()
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.hasSeenMinorSafetyScreen)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.pendingMinorSafetyScreen)
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("preventiveTasks_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Helpers

    private var initials: String {
        let parts = userName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(userName.prefix(2)).uppercased()
    }

    /// Opens the mail composer prefilled with the app version for faster debugging (audit #84).
    private func contactSupport() {
        let subject = "COIL Support"
        let body = "\n\n———\n\(appVersionText)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:noyfisher2003@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }

    /// Requests an App Store review via the system prompt (audit #84).
    private func requestAppReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        // SKStoreReviewController was deprecated in iOS 18; the deployment
        // target is 18.2, so the StoreKit 2 entry point is always available.
        AppStore.requestReview(in: scene)
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "COIL v\(version) (\(build))"
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var profileCard: some View {
        VStack(spacing: AppSpacing.lg) {
            // Avatar
            Text(initials)
                .font(AppFonts.heroTitle)
                .foregroundColor(AppColors.ctaText)
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(AppColors.primaryGradient)
                )

            Text(userName.isEmpty ? "User" : userName)
                .font(AppFonts.sectionTitle)
                .foregroundColor(AppColors.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.xl)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.xl)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 32, height: 32)
                    .background(AppColors.accentTint)
                    .cornerRadius(AppCorners.small)

                Text("Appearance")
                    .font(AppFonts.body)

                Spacer()
            }

            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearancePicker")
            .onChange(of: appearanceRaw) { _, newValue in
                AnalyticsService.shared.log(.settingChanged,
                    parameters: ["key": "appearance", "value": newValue])
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.xl)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.xl)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var debugFeedbackCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "ladybug", color: AppColors.accent, title: "Export Debug Log") {
                if let url = SessionLogger.shared.exportAsShareableFile() {
                    shareURL = url
                    showShareSheet = true
                }
            }

            Divider().padding(.leading, 52)

            HStack(spacing: AppSpacing.md) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accentLight)
                    .frame(width: 32, height: 32)
                    .background(AppColors.accentTint)
                    .cornerRadius(AppCorners.small)

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text("Session Events")
                        .font(AppFonts.body)
                    Text("\(SessionLogger.shared.eventCount) events this session")
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.large)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var helpSupportCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "envelope", color: AppColors.accent, title: "Contact Support") {
                contactSupport()
            }
            .accessibilityIdentifier("settings.contactSupportButton")

            Divider().padding(.leading, 52)

            settingsRow(icon: "flag", color: AppColors.warning, title: "Report a Concern") {
                showReportConcern = true
            }
            .accessibilityIdentifier("settings.reportConcernButton")

            Divider().padding(.leading, 52)

            settingsRow(icon: "shield.checkered", color: AppColors.accent, title: "Safety Resources") {
                showSafetyResources = true
            }
            .accessibilityIdentifier("settings.safetyResourcesButton")

            Divider().padding(.leading, 52)

            settingsRow(icon: "star", color: AppColors.accent, title: "Rate COIL") {
                requestAppReview()
            }
            .accessibilityIdentifier("settings.rateAppButton")
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.large)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded
    /// (adding the conditional withdraw row inline pushed the main VStack over the
    /// compiler's reasonable-time threshold).
    @ViewBuilder
    private var actionsCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "heart.text.clipboard", color: AppColors.accent, title: "Update Health Info") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onEditProfile()
                }
            }
            .accessibilityIdentifier("settings.editProfileButton")

            #if DEBUG
            Divider().padding(.leading, 52)

            NavigationLink(destination: MissingImagesDebugView()) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.warning)
                        .frame(width: 32, height: 32)
                        .background(AppColors.warning.opacity(0.12))
                        .cornerRadius(AppCorners.small)
                    Text("Image Diagnostics (DEBUG)")
                        .font(AppFonts.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
            .accessibilityIdentifier("settings.imageDiagnosticsButton")
            #endif

            Divider().padding(.leading, 52)

            settingsRow(icon: "rectangle.portrait.and.arrow.right", color: AppColors.danger, title: "Sign Out") {
                showSignOutConfirmation = true
            }
            .accessibilityIdentifier("settings.signOutButton")
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.large)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var dangerZoneCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "trash", color: AppColors.danger, title: "Delete Account") {
                showDeleteConfirmation = true
            }
            .accessibilityIdentifier("settings.deleteAccountButton")
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.large)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded
    /// (adding the conditional withdraw row inline pushed the main VStack over the
    /// compiler's reasonable-time threshold).
    @ViewBuilder
    private var notificationsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.warning)
                    .frame(width: 32, height: 32)
                    .background(AppColors.warning.opacity(0.12))
                    .cornerRadius(AppCorners.small)

                Text("Reminders")
                    .font(AppFonts.body)

                Spacer()

                Toggle("", isOn: $notificationService.isEnabled)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.reminderToggle")
                    .onChange(of: notificationService.isEnabled) { _, enabled in
                        AnalyticsService.shared.log(.settingChanged,
                            parameters: ["key": "reminders_enabled",
                                         "value": enabled ? "true" : "false"])
                        if enabled {
                            Task {
                                if !notificationService.isAuthorized {
                                    _ = await notificationService.requestPermission()
                                }
                                await notificationService.resyncReminders()
                            }
                        } else {
                            notificationService.cancelAllReminders()
                        }
                    }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)

            if notificationService.isEnabled {
                Divider().padding(.leading, 52)

                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                        .frame(width: 32, height: 32)
                        .background(AppColors.accentTint)
                        .cornerRadius(AppCorners.small)

                    Text("Reminder Time")
                        .font(AppFonts.body)

                    Spacer()

                    DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: reminderDate) { _, newDate in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            notificationService.updateReminderTime(hour: components.hour ?? 9, minute: components.minute ?? 0)
                            let timeString = String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "reminder_time", "value": timeString])
                        }
                        .onAppear {
                            // Seed the picker from the SAVED time so a glance or an
                            // accidental tap can't silently overwrite it (audit #81).
                            var comps = DateComponents()
                            comps.hour = notificationService.reminderHour
                            comps.minute = notificationService.reminderMinute
                            if let seeded = Calendar.current.date(from: comps) {
                                reminderDate = seeded
                            }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                Divider().padding(.leading, 52)

                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.success)
                        .frame(width: 32, height: 32)
                        .background(AppColors.success.opacity(0.12))
                        .cornerRadius(AppCorners.small)
                    Text("Workout Reminders")
                        .font(AppFonts.body)
                    Spacer()
                    Toggle("", isOn: $notificationService.workoutRemindersEnabled)
                        .labelsHidden()
                        .onChange(of: notificationService.workoutRemindersEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "workout_reminders",
                                             "value": enabled ? "true" : "false"])
                            Task { await notificationService.resyncReminders() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                Divider().padding(.leading, 52)

                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                        .frame(width: 32, height: 32)
                        .background(AppColors.accentTint)
                        .cornerRadius(AppCorners.small)
                    Text("Re-Assessment Prompts")
                        .font(AppFonts.body)
                    Spacer()
                    Toggle("", isOn: $notificationService.reassessmentRemindersEnabled)
                        .labelsHidden()
                        .onChange(of: notificationService.reassessmentRemindersEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "reassessment_reminders",
                                             "value": enabled ? "true" : "false"])
                            Task { await notificationService.resyncReminders() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                Divider().padding(.leading, 52)

                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "bell.badge.waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.warning)
                        .frame(width: 32, height: 32)
                        .background(AppColors.warning.opacity(0.12))
                        .cornerRadius(AppCorners.small)
                    Text("Inactivity Nudges")
                        .font(AppFonts.body)
                    Spacer()
                    Toggle("", isOn: $notificationService.inactivityNudgesEnabled)
                        .labelsHidden()
                        .onChange(of: notificationService.inactivityNudgesEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "inactivity_nudges",
                                             "value": enabled ? "true" : "false"])
                            if !enabled { notificationService.cancelInactivityNudge() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.large)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded
    /// (adding the conditional withdraw row inline pushed the main VStack over the
    /// compiler's reasonable-time threshold).
    @ViewBuilder
    private var legalCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "hand.raised", color: AppColors.accent, title: "Privacy Policy") {
                showPrivacyPolicy = true
            }
            .accessibilityIdentifier("settings.privacyPolicyButton")

            Divider().padding(.leading, 52)

            settingsRow(icon: "doc.text", color: AppColors.accent, title: "Terms of Service") {
                showTermsOfService = true
            }
            .accessibilityIdentifier("settings.termsOfServiceButton")

            Divider().padding(.leading, 52)

            settingsRow(icon: "heart.text.square", color: AppColors.accent, title: "Consumer Health Data Policy") {
                showConsumerHealthDataPolicy = true
            }
            .accessibilityIdentifier("settings.consumerHealthDataPolicyButton")

            if consentService.hasHealthDataConsent {
                Divider().padding(.leading, 52)
                settingsRow(icon: "heart.slash", color: AppColors.danger, title: "Withdraw Health Data Consent") {
                    showWithdrawConsentConfirmation = true
                }
                .accessibilityIdentifier("settings.withdrawHealthConsentButton")
            }
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.large)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    private func settingsRow(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .cornerRadius(AppCorners.small)

                Text(title)
                    .font(AppFonts.body)
                    .foregroundColor(title == "Sign Out" ? AppColors.danger : AppColors.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
    }
}
