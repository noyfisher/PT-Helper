import SwiftUI
import FirebaseAuth
import FirebaseCrashlytics

struct RootView: View {
    @State private var signedIn = (Auth.auth().currentUser != nil)
    @State private var profileCompleted = false
    @State private var isCheckingProfile = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasLoggedSignIn = false
    @StateObject private var profileService = UserProfileService.shared
    @StateObject private var consentService = ConsentService.shared
    /// Drives the launch-time ToS re-acceptance gate (production branch only).
    @State private var showLegalGate = false
    /// Drives the launch-time MHMDA health-data consent gate (production branch only).
    @State private var showHealthGate = false
    /// Drives the skip-onboarding legal + age gate (production branch only).
    @State private var showSkipGate = false
    /// Set by the skip gate when a 13–17 DOB is entered, or by
    /// checkProfileCompletion for a minor who completed onboarding; drives the
    /// one-time minor-safety interstitial (production branch only).
    @AppStorage(AppStorageKeys.pendingMinorSafetyScreen) private var pendingMinorSafetyScreen = false
    /// True once the minor-safety interstitial has been shown (so it appears once).
    @AppStorage(AppStorageKeys.hasSeenMinorSafetyScreen) private var hasSeenMinorSafetyScreen = false
    @AppStorage("hasSeenIntroCarousel") private var hasSeenIntroCarousel = false
    /// Set when the user taps Skip on onboarding, so the choice survives a
    /// relaunch instead of re-trapping them in the questionnaire every launch.
    @AppStorage("skippedOnboarding") private var skippedOnboarding = false
    /// Set when the user *completes* onboarding, so the app hands them straight
    /// into their first assessment (consumed + cleared by ThreeTabView).
    @AppStorage("pendingFirstAssessment") private var pendingFirstAssessment = false

    /// UI testing mode: bypass Firebase Auth and route based on launch arguments.
    /// Virtual user mode (`--virtual-user-token`) takes precedence: it must use
    /// the real production auth path, so the uitesting bypass is disabled.
    private var isUITesting: Bool {
        TestDataSeeder.isUITesting && TestDataSeeder.virtualUserToken == nil
    }

    @State private var hasAttemptedVirtualSignIn = false
    /// Retained so exactly one auth-state listener is registered for this view's
    /// lifetime (P2-05) — onAppear can fire again and would otherwise stack
    /// duplicate listeners.
    @State private var authListenerHandle: AuthStateDidChangeListenerHandle?

    var body: some View {
        Group {
            if isUITesting {
                uiTestingContent
            } else {
                productionContent
            }
        }
        .alert("Connection Error", isPresented: $showError) {
            Button("Retry") {
                isCheckingProfile = true
                checkProfileCompletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            guard !isUITesting else { return }
            // Register exactly one auth-state listener for this view's lifetime.
            // onAppear can fire again on re-presentation; without this guard each
            // fire stacked a duplicate listener → repeated session starts / cleanup
            // (P2-05). Root view lives for the app's lifetime, so it is not removed.
            guard authListenerHandle == nil else { return }
            authListenerHandle = Auth.auth().addStateDidChangeListener { _, user in
                signedIn = (user != nil)
                if let user = user {
                    SessionLogger.shared.startSession(userId: user.uid)
                    Crashlytics.crashlytics().setUserID(user.uid)
                    AnalyticsService.shared.setUserId(user.uid)
                    if !hasLoggedSignIn {
                        hasLoggedSignIn = true
                        AnalyticsService.shared.log(.signInCompleted)
                    }
                    Task { await ConsentService.shared.load() }
                    checkProfileCompletion()
                } else {
                    // Finalize + clear the signing-out user's session log so it
                    // can't upload under the next account or bleed into their
                    // session (P1-03). Logs `.signedOut` internally.
                    AccountSessionContext.signOutCleanup()
                    Crashlytics.crashlytics().setUserID("")
                    AnalyticsService.shared.setUserId(nil)
                    // FCM token is cleared at the sign-out ACTION while still
                    // authenticated (see SettingsView) — by the time this listener
                    // fires the user is nil and the Firestore write would be denied.
                    NotificationService.shared.cancelAllReminders()
                    OnboardingViewModel.clearDraft()
                    profileCompleted = false
                    // Reset the skip flag so a different account on this device
                    // isn't silently auto-skipped past onboarding.
                    skippedOnboarding = false
                    isCheckingProfile = true
                    profileService.clear()
                    // PHI: the last-analysis file must not survive into another account's
                    // session — the Progress tab's "Your Last Analysis" card reads it (WS6-01).
                    AnalysisResultStore.shared.clear()
                    ConsentService.clearLocalMirrors()
                }
            }
            attemptVirtualUserSignInIfNeeded()
        }
    }

    /// Signs in with a custom token when launched in virtual user mode.
    /// Runs after the auth state listener is registered so the resulting
    /// state change is observed like any real sign-in. Signs out any
    /// previously persisted user so the token's vuser always wins.
    private func attemptVirtualUserSignInIfNeeded() {
        guard let token = TestDataSeeder.virtualUserToken, !hasAttemptedVirtualSignIn else { return }
        hasAttemptedVirtualSignIn = true
        Task {
            do {
                if Auth.auth().currentUser != nil {
                    try Auth.auth().signOut()
                }
                let result = try await Auth.auth().signIn(withCustomToken: token)
                print("[VirtualUser] signed in as \(result.user.uid)")
            } catch {
                print("[VirtualUser] sign-in failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UI Testing Content

    @ViewBuilder
    private var uiTestingContent: some View {
        if TestDataSeeder.showIntroCarousel {
            IntroCarouselView(onComplete: {})
        } else if TestDataSeeder.shouldSkipOnboarding || profileCompleted {
            MainTabView()
        } else {
            OnboardingView(onComplete: {
                profileCompleted = true
            }, onSkip: {
                profileCompleted = true
            })
        }
    }

    // MARK: - Production Content

    @ViewBuilder
    private var productionContent: some View {
        if signedIn {
            if isCheckingProfile {
                ZStack {
                    AppColors.bgGradient
                        .ignoresSafeArea()
                    VStack(spacing: AppSpacing.xl) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(AppColors.accent)
                            .symbolEffect(.pulse.byLayer, options: .repeating)

                        Text("Loading your profile...")
                            .font(.subheadline)
                            // Bare text on the fixed-dark bgGradient — the first
                            // thing a returning user sees on every cold launch.
                            .foregroundColor(AppColors.textOnDarkMuted)
                    }
                }
            } else if profileCompleted || skippedOnboarding {
                MainTabView()
                    .fullScreenCover(isPresented: $showLegalGate) {
                        LegalAcceptanceGateView(mode: .reacceptance) { _ in showLegalGate = false }
                    }
                    .fullScreenCover(isPresented: $pendingMinorSafetyScreen) {
                        MinorSafetyResourcesView {
                            pendingMinorSafetyScreen = false
                            hasSeenMinorSafetyScreen = true
                        }
                    }
                    .fullScreenCover(isPresented: $showHealthGate) {
                        HealthDataConsentView(
                            onConsented: { showHealthGate = false },
                            onDeclineSignOut: {
                                showHealthGate = false
                                try? Auth.auth().signOut()
                            })
                    }
                    .onChange(of: consentService.isLoaded) { _, loaded in
                        if loaded && consentService.needsLegalReacceptance { showLegalGate = true }
                        reevaluateHealthGate()
                    }
                    .onAppear {
                        if consentService.isLoaded && consentService.needsLegalReacceptance { showLegalGate = true }
                        reevaluateHealthGate()
                    }
                    .onChange(of: showLegalGate) { _, _ in reevaluateHealthGate() }
                    .onChange(of: pendingMinorSafetyScreen) { _, _ in reevaluateHealthGate() }
                    .onChange(of: isCheckingProfile) { _, _ in reevaluateHealthGate() }
            } else if !hasSeenIntroCarousel {
                IntroCarouselView(onComplete: {
                    hasSeenIntroCarousel = true
                })
            } else {
                OnboardingView(onComplete: {
                    pendingFirstAssessment = true
                    profileCompleted = true
                }, onSkip: {
                    showSkipGate = true
                })
                .fullScreenCover(isPresented: $showSkipGate) {
                    LegalAcceptanceGateView(mode: .skipOnboarding) { dob in
                        if let dob, AgePolicy.isMinor(dateOfBirth: dob) {
                            pendingMinorSafetyScreen = true
                        }
                        showSkipGate = false
                        skippedOnboarding = true
                        profileCompleted = true
                    }
                }
            }
        } else {
            LoginView(onSignedIn: { signedIn = true })
        }
    }

    /// Re-evaluates the launch-time MHMDA gate. Accepted, documented limitation:
    /// if consent is revoked mid-session, ungated downstream flows stay open
    /// until next launch — immediate coverage is provided by the three
    /// point-of-use gates (OnboardingView, WellnessGoalPickerView, BodyMap3DView).
    private func reevaluateHealthGate() {
        showHealthGate = ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: consentService.isLoaded,
            needsLegalReacceptance: consentService.needsLegalReacceptance,
            legalGateShowing: showLegalGate,
            minorSafetyPending: pendingMinorSafetyScreen,
            hasHealthProfile: profileService.profile != nil,
            hasHealthDataConsent: consentService.hasHealthDataConsent)
    }

    private func checkProfileCompletion() {
        Task {
            let exists = await profileService.checkProfileExists()
            if let error = profileService.loadError {
                errorMessage = error
                showError = true
            }
            profileCompleted = exists
            isCheckingProfile = false
            if exists, let profile = profileService.profile {
                AnalyticsService.shared.setUserProperties(hasProfile: true)
                // Minors see the safety interstitial once after landing in the app.
                if AgePolicy.isMinor(dateOfBirth: profile.dateOfBirth), !hasSeenMinorSafetyScreen {
                    pendingMinorSafetyScreen = true
                }
            }
        }
    }
}
