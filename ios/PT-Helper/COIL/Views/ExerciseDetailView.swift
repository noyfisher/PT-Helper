import SwiftUI

struct ExerciseDetailView: View {
    let exercise: RehabExercise

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    demonstrationIcon
                    positionGuide
                    exerciseInfo
                    formTips
                    contraindications
                    if exercise.reps.contains("seconds") {
                    }
                }
                .padding(AppSpacing.xl)
                .floatingTabBarClearance()
            }
        }
        .trackScreen("ExerciseDetail")
    }

    private var demonstrationIcon: some View {
        ExerciseImagePagerView(exercise: exercise)
    }

    private var positionGuide: some View {
        Group {
            if exercise.startPosition != nil || exercise.movement != nil || exercise.endPosition != nil {
                CardSection(icon: "figure.walk.motion", color: AppColors.accent, title: "How to Do It") {
                    ExercisePositionGuideView(
                        startPosition: exercise.startPosition,
                        movement: exercise.movement,
                        endPosition: exercise.endPosition
                    )
                }
            }
        }
    }

    private var exerciseInfo: some View {
        CardSection(icon: "info.circle", color: AppColors.accent, title: exercise.name) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Target Area: \(exercise.targetArea)")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)
                Text(exercise.description)
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.primaryText)
                HStack {
                    Text("Sets: \(exercise.sets)")
                    Text("Reps: \(exercise.reps)")
                    Text("Rest: \(exercise.restSeconds) sec")
                }
                .font(AppFonts.caption)
                .foregroundColor(AppColors.secondaryText)
            }
        }
    }

    // Empty for many AI-generated / swapped exercises — don't render a bare
    // labeled box (a blank "Contraindications" card reads as "no safety
    // concerns") when there's nothing to show (audit #55).
    @ViewBuilder
    private var formTips: some View {
        if !exercise.tips.isEmpty {
            CardSection(icon: "lightbulb", color: AppColors.warning, title: "Form Tips") {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(exercise.tips, id: \.self) { tip in
                        Text("- \(tip)")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contraindications: some View {
        if !exercise.contraindications.isEmpty {
            CardSection(icon: "exclamationmark.triangle", color: AppColors.danger, title: "Contraindications") {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(exercise.contraindications, id: \.self) { contraindication in
                        Text("- \(contraindication)")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
    }

}
