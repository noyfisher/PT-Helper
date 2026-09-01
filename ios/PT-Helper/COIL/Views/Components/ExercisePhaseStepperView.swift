import SwiftUI

/// Interactive 3-step instruction stepper showing Setup → Move → Return
/// one phase at a time. Handles nil fields gracefully — only shows
/// non-nil phases, and falls back to exercise description if all are nil.
struct ExercisePhaseStepperView: View {
    /// Identity of the exercise being described. The stepper occupies the same
    /// structural position for every exercise in a guided workout, so without an
    /// explicit reset its `@State` survives the exercise change: advancing to a new
    /// exercise kept the previously selected phase, opening instructions on "Return
    /// Position" (or on a phase the new exercise doesn't have).
    var exerciseIdentity: String = ""

    let startPosition: String?
    let movement: String?
    let endPosition: String?
    let exerciseDescription: String?
    @Binding var isExpanded: Bool
    @State private var activePhase: Int = 0

    private var phases: [(label: String, text: String)] {
        var result: [(String, String)] = []
        if let start = startPosition { result.append(("Setup", start)) }
        if let move = movement { result.append(("Move", move)) }
        if let end = endPosition { result.append(("Return", end)) }
        return result
    }

    private var hasPhases: Bool { !phases.isEmpty }

    var body: some View {
        Group {
            if isExpanded {
                if hasPhases {
                    phaseStepperContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let desc = exerciseDescription, !desc.isEmpty {
                    descriptionFallback(desc)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        // Fires even while collapsed, so re-expanding on a new exercise starts at
        // the first phase rather than wherever the previous exercise was left.
        .onChange(of: exerciseIdentity) { _, _ in
            activePhase = 0
        }
    }

    // MARK: - Phase Stepper

    private var phaseStepperContent: some View {
        VStack(spacing: AppSpacing.md) {
            // Phase pills
            HStack(spacing: 6) {
                ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                    Button {
                        withAnimation(AppAnimations.smooth) {
                            activePhase = index
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("STEP \(index + 1)")
                                .font(AppFonts.badge)
                                .opacity(0.7)
                            Text(phase.label)
                                .font(AppFonts.captionSemiBold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.comfortable)
                        .background(index == activePhase ? AppColors.accent : AppColors.accentTint)
                        .foregroundColor(index == activePhase ? .white : AppColors.accent)
                        .cornerRadius(AppCorners.small)
                    }
                }
            }

            // Active phase content
            if activePhase < phases.count {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(phases[activePhase].text)
                        .font(AppFonts.small)
                        .foregroundColor(AppColors.primaryText)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)
            }
        }
    }

    // MARK: - Description Fallback

    private func descriptionFallback(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(description)
                .font(AppFonts.small)
                .foregroundColor(AppColors.secondaryText)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)
    }
}
