import SwiftUI

/// Standalone MHMDA opt-in consent for collecting AND sharing health data.
/// Blocking (`interactiveDismissDisabled()`); the parent binding drives dismissal
/// via the `onConsented` callback — this view holds NO `@Environment(\.dismiss)`
/// (see Gotchas #1). Both checkboxes must be ticked before Continue is enabled.
struct HealthDataConsentView: View {
    let onConsented: () -> Void
    var onDeclineSignOut: (() -> Void)? = nil
    /// Point-of-use presentations (body map, wellness picker) pass this so the
    /// sheet has a decline path: the user returns to browsing without granting
    /// consent. Without it — and with `interactiveDismissDisabled()` — the sheet
    /// had no cancel, no back, and no swipe: a consent screen you can only
    /// accept is not consent.
    var onNotNow: (() -> Void)? = nil

    @State private var consentCollection = false
    @State private var consentSharing = false
    @State private var showPolicy = false

    private var canContinue: Bool {
        consentCollection && consentSharing
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.coolGradient)
                            .padding(.top, AppSpacing.xxl)

                        Text("Your Health Data")
                            .font(AppFonts.title)

                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            consentSection(
                                icon: "heart.text.square.fill",
                                color: AppColors.accent,
                                title: "What we collect",
                                text: "Your health profile (age, sex, height, weight, medical conditions, medications, surgeries, injuries), your pain and wellness assessments, and movement metrics from form-check videos."
                            )

                            consentSection(
                                icon: "gearshape.fill",
                                color: AppColors.success,
                                title: "How we use it",
                                text: "To generate your educational analysis, exercise plans, and progress insights. We never sell your health data or use it for advertising."
                            )
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        Button("Read the full Consumer Health Data Privacy Policy") {
                            showPolicy = true
                        }
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.xl)

                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            consentCheckbox(
                                isOn: $consentCollection,
                                label: "I consent to the collection and use of my health data as described above and in the Consumer Health Data Privacy Policy.",
                                identifier: "healthConsent.collectionCheckbox"
                            )

                            consentCheckbox(
                                isOn: $consentSharing,
                                label: "I consent to my health data being shared with the AI-processing providers named in the policy (Anthropic, and OpenAI for exercise-safety checks) so the app can generate my analysis and plans.",
                                identifier: "healthConsent.sharingCheckbox"
                            )
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        Text("You can withdraw consent at any time in Settings, by deleting your account, or by emailing noyfisher2003@gmail.com.")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.xl)

                        Button(action: {
                            ConsentService.shared.recordHealthDataConsent()
                            onConsented()
                        }) {
                            Text("Continue")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.lg)
                                .background(canContinue ? AppColors.accent : AppColors.accent.opacity(0.4))
                                .foregroundColor(AppColors.ctaText)
                                .font(AppFonts.cardTitle)
                                .cornerRadius(AppCorners.large)
                        }
                        .disabled(!canContinue)
                        .accessibilityIdentifier("healthConsent.continueButton")
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.lg)

                        if let onNotNow {
                            Button("Not Now") {
                                onNotNow()
                            }
                            .font(AppFonts.bodyMedium)
                            .foregroundColor(AppColors.secondaryText)
                            .accessibilityIdentifier("healthConsent.notNowButton")
                            .padding(.top, AppSpacing.sm)
                        }

                        if let onDeclineSignOut {
                            VStack(spacing: AppSpacing.xs) {
                                Button("Sign out instead") {
                                    onDeclineSignOut()
                                }
                                .font(AppFonts.bodyMedium)
                                .foregroundColor(AppColors.secondaryText)
                                .accessibilityIdentifier("healthConsent.signOutButton")

                                Text("If you don't consent, COIL can't provide assessments or plans. You can also email noyfisher2003@gmail.com to request deletion of your data.")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, AppSpacing.xl)
                            }
                            .padding(.top, AppSpacing.sm)
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Health Data Consent")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showPolicy) {
            LegalDocumentView(title: "Consumer Health Data Policy", markdownContent: LegalContent.consumerHealthDataPolicy)
        }
        .trackScreen("HealthDataConsent")
    }

    // MARK: - Components

    private func consentSection(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFonts.smallSemiBold)
                Text(text)
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func consentCheckbox(isOn: Binding<Bool>, label: String, identifier: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isOn.wrappedValue ? AppColors.accent : AppColors.secondaryText)
            }
            .accessibilityIdentifier(identifier)

            Text(label)
                .font(AppFonts.body)
                .foregroundColor(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HealthDataConsentView(onConsented: {})
}
