import SwiftUI
import UIKit

// MARK: - Onboarding Edit Wrapper (for updating profile from home)
struct OnboardingEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var isLoading = true

    var body: some View {
        ZStack {
            AppColors.bgGradient
                .ignoresSafeArea()

            if isLoading {
                VStack(spacing: AppSpacing.md) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("Loading your profile...")
                        .font(AppFonts.small)
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Top bar with close button
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                        Spacer()
                        Text("Update Profile")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.sm)

                    // Step indicator
                    VStack(spacing: AppSpacing.lg) {
                        Text("Step \(viewModel.currentStep) of 6")
                            .font(AppFonts.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.ctaText)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .background(AppColors.accent)
                            .clipShape(Capsule())

                        HStack(spacing: AppSpacing.tight) {
                            ForEach(1...6, id: \.self) { step in
                                Capsule()
                                    .fill(step <= viewModel.currentStep ? AppColors.accent : Color.white.opacity(0.15))
                                    .frame(height: 5)
                                    .animation(.spring(response: 0.35), value: viewModel.currentStep)
                            }
                        }
                        .padding(.horizontal, 32)

                        Text(stepTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text(stepSubtitle)
                            .font(AppFonts.body)
                            .foregroundColor(Color.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 8)

                    // Step content
                    TabView(selection: $viewModel.currentStep) {
                        BasicInfoStepView(viewModel: viewModel).tag(1)
                        MedicalHistoryStepView(viewModel: viewModel).tag(2)
                        SurgicalHistoryStepView(viewModel: viewModel).tag(3)
                        InjuryHistoryStepView(viewModel: viewModel).tag(4)
                        ActivityLevelStepView(viewModel: viewModel).tag(5)
                        ProfileReviewStepView(viewModel: viewModel, onComplete: {
                            dismiss()
                        }).tag(6)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    // Same swipe bypass as OnboardingView — buttons-only here too.
                    .scrollDisabled(true)
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
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
        }
        .onAppear {
            // This flow lays its TabView out in a different order than onboarding
            // (Basic, Medical, Surgical, Injury, Activity, Review). Validation is
            // keyed on step identity via this order — without it, step 2 (Medical)
            // was validated against the Activity rule and Activity never at all.
            viewModel.stepOrder = OnboardingViewModel.Step.editOrder
            viewModel.loadProfile { success in
                viewModel.currentStep = 1
                isLoading = false
            }
        }
    }

    private var stepTitle: String {
        switch viewModel.currentStep {
        case 1: return "About You"
        case 2: return "Medical History"
        case 3: return "Past Surgeries"
        case 4: return "Injuries"
        case 5: return "Activity Level"
        case 6: return "Review & Submit"
        default: return ""
        }
    }

    private var stepSubtitle: String {
        switch viewModel.currentStep {
        case 1: return "Let's start with some basic information"
        case 2: return "Adding your medical history helps our AI provide safer, more accurate recommendations"
        case 3: return "Past surgeries help us avoid exercises that could cause re-injury"
        case 4: return "Current or past injuries help us tailor your rehab plan"
        case 5: return "How active are you day to day?"
        case 6: return "Make sure everything looks correct"
        default: return ""
        }
    }
}
