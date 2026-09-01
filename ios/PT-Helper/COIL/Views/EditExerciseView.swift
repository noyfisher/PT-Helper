import SwiftUI

/// Sheet for editing a single exercise's mutable properties.
struct EditExerciseView: View {
    @Binding var exercise: RehabExercise
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sets: Int = 3
    @State private var reps: String = "10"
    @State private var restSeconds: Int = 30
    @State private var description: String = ""
    @State private var difficulty: RehabExercise.Difficulty = .beginner

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Name
                        CardSection(icon: "textformat", color: AppColors.accent, title: "Exercise Name") {
                            TextField("Exercise name", text: $name)
                                .font(AppFonts.body)
                                .padding(AppSpacing.md)
                                .background(AppColors.inputBackground)
                                .cornerRadius(AppCorners.medium)
                        }

                        // Sets & Reps
                        CardSection(icon: "arrow.triangle.2.circlepath", color: AppColors.success, title: "Sets & Reps") {
                            VStack(spacing: AppSpacing.md) {
                                HStack {
                                    Text("Sets")
                                        .font(AppFonts.small)
                                    Spacer()
                                    Stepper("\(sets)", value: $sets, in: 1...10)
                                        .fixedSize()
                                }

                                HStack {
                                    Text("Reps")
                                        .font(AppFonts.small)
                                    Spacer()
                                    TextField("Reps", text: $reps)
                                        .font(AppFonts.body)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                        .padding(AppSpacing.sm)
                                        .background(AppColors.inputBackground)
                                        .cornerRadius(AppCorners.small)
                                }

                                HStack {
                                    Text("Rest (seconds)")
                                        .font(AppFonts.small)
                                    Spacer()
                                    Stepper("\(restSeconds)s", value: $restSeconds, in: 5...180, step: 5)
                                        .fixedSize()
                                }
                            }
                        }

                        // Difficulty
                        CardSection(icon: "gauge.with.dots.needle.33percent", color: AppColors.warning, title: "Difficulty") {
                            Picker("Difficulty", selection: $difficulty) {
                                ForEach(RehabExercise.Difficulty.allCases, id: \.self) { level in
                                    Text(level.rawValue.capitalized).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Description
                        CardSection(icon: "text.alignleft", color: AppColors.accent, title: "Description") {
                            TextField("Exercise description", text: $description, axis: .vertical)
                                .lineLimit(3...8)
                                .padding(AppSpacing.md)
                                .background(AppColors.inputBackground)
                                .cornerRadius(AppCorners.medium)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        exercise.name = trimmedName
                        exercise.sets = sets
                        exercise.reps = reps
                        exercise.restSeconds = restSeconds
                        exercise.description = description
                        exercise.difficulty = difficulty
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    // Exercise NAME is the key for image resolution, the
                    // contraindication checker and the knowledge-graph lookup, so
                    // saving an empty one silently detaches the exercise from every
                    // one of those. Saving is blocked rather than silently
                    // substituted, so the user sees what they are fixing.
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .onAppear {
            name = exercise.name
            sets = exercise.sets
            reps = exercise.reps
            restSeconds = exercise.restSeconds
            description = exercise.description
            difficulty = exercise.difficulty
        }
        .trackScreen("EditExercise")
    }
}
