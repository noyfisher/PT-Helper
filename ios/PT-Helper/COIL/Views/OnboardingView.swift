import SwiftUI
import FirebaseAuth

struct OnboardingView: View {
    var onComplete: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.scenePhase) private var scenePhase
    /// MHMDA health-data consent must be granted before any health data is entered.
    @State private var showHealthConsent = false

    var body: some View {
        ZStack {
            AppColors.bgGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with skip
                HStack {
                    Spacer()
                    if let onSkip = onSkip {
                        Button(action: {
                            AnalyticsService.shared.log(.onboardingSkipped, parameters: ["skipped_at_step": viewModel.currentStep])
                            OnboardingViewModel.clearDraft()
                            onSkip()
                        }) {
                            Text("Skip")
                                .font(AppFonts.bodyMedium)
                                .foregroundColor(Color.white.opacity(0.40))
                        }
                        .accessibilityIdentifier("onboarding.skipButton")
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)

                // Step indicator header
                VStack(spacing: AppSpacing.md) {
                    HStack(spacing: AppSpacing.xl) {
                        HStack(spacing: 5) {
                            ForEach(1...6, id: \.self) { step in
                                Capsule()
                                    .fill(step <= viewModel.currentStep ? AppColors.accent : Color.white.opacity(0.15))
                                    .frame(height: 3)
                                    .animation(.spring(response: 0.35), value: viewModel.currentStep)
                            }
                        }
                        Text("\(viewModel.currentStep)/6")
                            .font(AppFonts.microMedium)
                            .foregroundColor(Color.white.opacity(0.30))
                            .monospacedDigit()
                            .accessibilityIdentifier("onboarding.stepIndicator")
                    }
                    .padding(.horizontal, AppSpacing.xxl)

                    VStack(spacing: AppSpacing.xs) {
                        Text(stepTitle)
                            .font(AppFonts.heroTitle)
                            .foregroundColor(.white)
                        Text(stepSubtitle)
                            .font(AppFonts.small)
                            .foregroundColor(Color.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xxl)
                        // Set expectations up front so the 6-step intake feels
                        // quick and low-stakes rather than a daunting medical form.
                        if viewModel.currentStep == 1 {
                            Text("About 2 minutes · skip anything that doesn't apply · progress saves automatically")
                                .font(AppFonts.microMedium)
                                .foregroundColor(Color.white.opacity(0.30))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.xxl)
                                .padding(.top, AppSpacing.nano)
                        }
                    }
                }
                .padding(.bottom, AppSpacing.sm)

                // Step content.
                //
                // Deliberately NOT a page-style TabView. That container is
                // horizontally swipeable by default, and a swipe writes
                // currentStep straight through the binding without consulting
                // canProceedFromCurrentStep — bypassing every gate on the way to
                // Review, including the 13+ age check and Terms acceptance.
                // `.scrollDisabled(true)` is the wrong tool for that: it
                // propagates through the environment and disables each step's OWN
                // ScrollView too, which made the form unscrollable and left the
                // Terms checkbox unreachable. Rendering only the current step
                // removes the paging gesture by construction and leaves the inner
                // ScrollViews alone. Navigation is buttons-only.
                Group {
                    switch viewModel.currentStep {
                    case 1: BasicInfoStepView(viewModel: viewModel)
                    case 2: ActivityLevelStepView(viewModel: viewModel)
                    case 3: MedicalHistoryStepView(viewModel: viewModel)
                    case 4: SurgicalHistoryStepView(viewModel: viewModel)
                    case 5: InjuryHistoryStepView(viewModel: viewModel)
                    default: ProfileReviewStepView(viewModel: viewModel, onComplete: onComplete)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

                // Navigation buttons
                HStack(spacing: AppSpacing.md) {
                    if viewModel.currentStep > 1 {
                        Button(action: { viewModel.previousStep() }) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Back")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("onboarding.backButton")
                    }

                    if viewModel.currentStep < 6 {
                        Button(action: {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            viewModel.nextStep()
                        }) {
                            HStack(spacing: AppSpacing.xs) {
                                Text("Continue")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: !viewModel.canProceedFromCurrentStep))
                        .disabled(!viewModel.canProceedFromCurrentStep)
                        .accessibilityIdentifier("onboarding.continueButton")
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)
            }
        }
        .onAppear {
            AnalyticsService.shared.log(.onboardingStarted)
            if viewModel.loadDraft() {
                AppLogger.data.info("Resumed onboarding draft at step \(viewModel.currentStep)")
            }
            if !ConsentService.shared.hasHealthDataConsent {
                showHealthConsent = true
            }
        }
        .fullScreenCover(isPresented: $showHealthConsent) {
            // Consent is required to collect the health profile, so "not now" is
            // not offered here — but the sheet must not be a trap either. Mirror
            // RootView's gate: the honest alternative is signing out.
            HealthDataConsentView(
                onConsented: { showHealthConsent = false },
                onDeclineSignOut: {
                    showHealthConsent = false
                    try? Auth.auth().signOut()
                })
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveDraft()
            }
        }
        .trackScreen("Onboarding")
        .preferredColorScheme(.dark) // hero screen is intentionally dark in both app modes
    }

    private var stepTitle: String {
        switch viewModel.currentStep {
        case 1: return "About You"
        case 2: return "Activity Level"
        case 3: return "Medical History"
        case 4: return "Past Surgeries"
        case 5: return "Injuries"
        case 6: return "Review & Submit"
        default: return ""
        }
    }

    private var stepSubtitle: String {
        switch viewModel.currentStep {
        case 1: return "Let's start with some basic information"
        case 2: return "How active are you day to day?"
        // Value-bridge copy: explain why a "performance" app asks for medical
        // history right after selling recovery, at the most fragile moment.
        case 3: return "We use this to keep every exercise safe for your body — never to diagnose you"
        case 4: return "Past procedures help us protect the area — optional, but useful"
        case 5: return "Current or past injuries help us tailor safely — optional"
        case 6: return "Make sure everything looks correct"
        default: return ""
        }
    }
}
