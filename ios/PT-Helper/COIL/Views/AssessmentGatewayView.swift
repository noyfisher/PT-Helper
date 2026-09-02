import SwiftUI

/// Lightweight dual gateway presented by the floating "+" and the app's
/// assessment CTAs. Lets the user choose the pain path (body-map assessment) or
/// the wellness path (goal picker) — the wellness side was previously unreachable
/// in the live 3-tab UI (audit #8).
///
/// Hosted inside `MainTabView`'s assessment `fullScreenCover` (which supplies the
/// `NavigationStack` and the close button). Crucially, picking a path swaps this
/// view's *root content in place* rather than pushing via `navigationDestination`:
/// `BodyMap3DView`'s RealityKit `RealityView` renders fine as a NavigationStack
/// root but crashes when pushed as a destination, so the selected destination
/// must become the stack root. Never reads `@Environment(\.dismiss)` (the cover
/// owns close) to avoid the SwiftUI dismiss+destination freeze.
struct AssessmentGatewayView: View {
    @ObservedObject private var profileService = UserProfileService.shared

    /// `nil` shows the chooser; a value swaps to that destination at the root.
    @State private var choice: AssessmentRoute?

    var body: some View {
        switch choice {
        case .pain:
            BodyMap3DView()
        case .wellness:
            if let profile = profileService.profile {
                WellnessGoalPickerView(userProfile: profile)
            } else {
                chooser
            }
        case .gateway, .none:
            chooser
        }
    }

    // MARK: - Chooser

    private var chooser: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                VStack(spacing: AppSpacing.xs) {
                    Text("What Can We Help With?")
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.primaryText)
                        .multilineTextAlignment(.center)
                    Text("Pick a path — both build a personalized plan with guided workouts.")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, AppSpacing.lg)

                HStack(alignment: .top, spacing: AppSpacing.md) {
                    Button {
                        AnalyticsService.shared.log(.assessmentGatewayChosen, parameters: ["path": "injury"])
                        choice = .pain
                    } label: {
                        gatewayCard(
                            icon: "figure.run.circle",
                            badge: "Start Assessment",
                            title: "Something Hurts",
                            subtitle: "Assess pain and get a recovery plan",
                            dark: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gateway.somethingHurtsButton")

                    if profileService.profile != nil {
                        Button {
                            AnalyticsService.shared.log(.assessmentGatewayChosen, parameters: ["path": "wellness"])
                            choice = .wellness
                        } label: {
                            gatewayCard(
                                icon: "sparkles",
                                badge: "Get Started",
                                title: "Improve My Life",
                                subtitle: "Sleep, posture, mobility & more",
                                dark: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("gateway.improveLifeButton")
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxxl)
        }
        .background(AppColors.pageBackground.ignoresSafeArea())
        .trackScreen("AssessmentGateway")
    }

    // MARK: - Gateway Card

    private func gatewayCard(icon: String, badge: String, title: String, subtitle: String, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AppColors.accent.opacity(dark ? 1 : 0.10).frame(height: 4)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.accent)
                    .padding(.top, AppSpacing.xs)

                Spacer(minLength: AppSpacing.sm)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppFonts.cardTitle)
                        .textCase(.uppercase)
                        .kerning(0.3)
                        .foregroundColor(dark ? .white : AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(AppFonts.micro)
                        .foregroundColor(dark ? .white.opacity(0.6) : AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text(badge)
                        .font(AppFonts.caption)
                        .textCase(.uppercase)
                        .kerning(0.5)
                        .foregroundColor(AppColors.accentText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
            }
            .padding(AppSpacing.lg)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(dark ? AppColors.darkSurface : AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(dark ? nil : RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(dark ? 0.14 : 0.06), radius: dark ? 16 : 8, y: dark ? 4 : 2)
    }
}
