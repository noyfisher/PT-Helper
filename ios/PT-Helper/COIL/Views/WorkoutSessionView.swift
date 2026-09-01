import SwiftUI

struct WorkoutSessionView: View {
    @EnvironmentObject private var viewModel: WorkoutViewModel
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @State private var painLevel: Double = 5
    @State private var durationMinutes: Double = 30
    @State private var notes: String = ""
    @State private var selectedExercises: Set<String> = []
    @State private var customExercise: String = ""
    @State private var showSavedConfirmation = false
    @State private var regionPainLevels: [String: Double] = [:]
    @State private var sessionToDelete: WorkoutSession?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            AppColors.pageBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Pain level
                    CardSection(icon: "waveform.path.ecg", color: painColor, title: "Pain Level") {
                        VStack(spacing: AppSpacing.md) {
                            HStack {
                                Text("\(Int(painLevel))")
                                    .font(AppFonts.display)
                                    .foregroundColor(painColor)
                                Text("/ 10")
                                    .font(AppFonts.sectionTitle)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text(painDescription)
                                    .font(AppFonts.bodyMedium)
                                    .foregroundColor(painColor)
                                    .padding(.horizontal, AppSpacing.md)
                                    .padding(.vertical, AppSpacing.xs)
                                    .background(painColor.opacity(0.12))
                                    .cornerRadius(AppCorners.small)
                            }

                            Slider(value: $painLevel, in: 0...10, step: 1)
                                .tint(painColor)
                                .accessibilityLabel("Pain level")
                                .accessibilityValue("\(Int(painLevel)) out of 10, \(painDescription)")

                            HStack {
                                Text("No pain")
                                    .font(AppFonts.micro)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text("Severe")
                                    .font(AppFonts.micro)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }

                    // Per-region pain tracking
                    RegionPainInputView(
                        regionPainLevels: $regionPainLevels,
                        suggestedRegions: suggestedRegions
                    )

                    // Duration
                    CardSection(icon: "timer", color: AppColors.warning, title: "Duration") {
                        VStack(spacing: AppSpacing.md) {
                            HStack {
                                Text("\(Int(durationMinutes))")
                                    .font(AppFonts.display)
                                    .foregroundColor(AppColors.warning)
                                Text("min")
                                    .font(AppFonts.sectionTitle)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                            }

                            Slider(value: $durationMinutes, in: 5...120, step: 5)
                                .tint(AppColors.warning)
                                .accessibilityLabel("Workout duration")
                                .accessibilityValue("\(Int(durationMinutes)) minutes")

                            HStack {
                                Text("5 min")
                                    .font(AppFonts.micro)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text("2 hours")
                                    .font(AppFonts.micro)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }

                    // Exercises performed
                    CardSection(icon: "figure.strengthtraining.traditional", color: AppColors.success, title: "Exercises Performed") {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            if !availableExercises.isEmpty {
                                Text("From your rehab plans:")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                ForEach(availableExercises, id: \.self) { name in
                                    Button(action: {
                                        if selectedExercises.contains(name) {
                                            selectedExercises.remove(name)
                                        } else {
                                            selectedExercises.insert(name)
                                        }
                                    }) {
                                        HStack(spacing: AppSpacing.sm) {
                                            Image(systemName: selectedExercises.contains(name) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedExercises.contains(name) ? AppColors.success : AppColors.secondaryText)
                                            Text(name)
                                                .font(AppFonts.body)
                                                .foregroundColor(AppColors.primaryText)
                                            Spacer()
                                        }
                                        .padding(.vertical, AppSpacing.xs)
                                    }
                                }
                            }

                            // Custom exercise input
                            HStack(spacing: AppSpacing.sm) {
                                TextField("Add other exercise...", text: $customExercise)
                                    .font(AppFonts.body)
                                    .padding(.horizontal, AppSpacing.md)
                                    .padding(.vertical, AppSpacing.sm)
                                    .background(AppColors.inputBackground)
                                    .cornerRadius(AppCorners.small)
                                    .submitLabel(.done)
                                    .onSubmit { addCustomExercise() }
                                Button(action: addCustomExercise) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(customExercise.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.mutedText : AppColors.success)
                                }
                                .disabled(customExercise.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            if !selectedExercises.isEmpty {
                                Text("\(selectedExercises.count) \(selectedExercises.count == 1 ? "exercise" : "exercises") selected")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.success)
                            }
                        }
                    }

                    // Notes
                    CardSection(icon: "note.text", color: AppColors.accent, title: "Session Notes") {
                        TextField("How did the session go?", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(AppSpacing.md)
                            .background(AppColors.inputBackground)
                            .cornerRadius(AppCorners.medium)
                    }

                    // Save button
                    Button(action: saveSession) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Session")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    // Session history
                    if viewModel.sessions.isEmpty {
                        EmptyStateView(
                            icon: "figure.strengthtraining.traditional",
                            title: "No Sessions Yet",
                            subtitle: "Log your first workout session above"
                        )
                    } else {
                        SectionHeader(icon: "clock.arrow.circlepath", color: AppColors.accent, title: "Recent Sessions")
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)

                if !viewModel.sessions.isEmpty {
                    List {
                        // `sessions` is already newest-first — the Firestore fetch
                        // orders by date descending and addSession inserts at index 0.
                        // reversed() turned "Recent Sessions" into oldest-first, so with
                        // the 180-document fetch cap a long-time user saw their stalest
                        // sessions at the top.
                        ForEach(viewModel.sessions, id: \.id) { session in
                            sessionCard(for: session)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        sessionToDelete = session
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: AppSpacing.xs, leading: AppSpacing.xl, bottom: AppSpacing.xs, trailing: AppSpacing.xl))
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: CGFloat(viewModel.sessions.count) * 90)
                }

                Color.clear.frame(height: FloatingTabBarMetrics.clearance)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Workout Session")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showSavedConfirmation {
                savedConfirmationOverlay
            }
        }
        .alert("Delete Session", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    withAnimation {
                        viewModel.deleteSession(session)
                    }
                    sessionToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this workout session? This cannot be undone.")
        }
        .achievementCelebration()
        .trackScreen("WorkoutSession")
        .persistenceFailureAlert($viewModel.saveFailure)
    }

    // MARK: - Helpers

    private func saveSession() {
        let session = WorkoutSession(
            id: UUID(),
            date: Date(),
            duration: durationMinutes * 60,
            painLevel: painLevel,
            isCompleted: true,
            exercisesPerformed: Array(selectedExercises),
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
            regionPainLevels: regionPainLevels.isEmpty ? nil : regionPainLevels
        )
        viewModel.addSession(session: session)

        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)

        withAnimation(AppAnimations.bouncy) {
            showSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showSavedConfirmation = false }
        }

        // Reset form
        painLevel = 5
        durationMinutes = 30
        notes = ""
        selectedExercises = []
        regionPainLevels = [:]
    }

    private func addCustomExercise() {
        let trimmed = customExercise.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        selectedExercises.insert(trimmed)
        customExercise = ""
    }

    /// Unique exercise names from all saved rehab plans
    private var availableExercises: [String] {
        let allNames = savedPlansVM.rehabPlans.flatMap { $0.exercises.map { $0.name } }
        return Array(Set(allNames)).sorted()
    }

    /// Suggested body regions from saved plans' target areas
    private var suggestedRegions: [String] {
        let allTargets = savedPlansVM.rehabPlans.flatMap { $0.exercises.map { $0.targetArea.lowercased().replacingOccurrences(of: " ", with: "_") } }
        return Array(Set(allTargets)).sorted()
    }

    private var painColor: Color {
        switch Int(painLevel) {
        case 0...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
        }
    }

    private var painDescription: String {
        switch Int(painLevel) {
        case 0: return "None"
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        case 7...8: return "Severe"
        default: return "Extreme"
        }
    }

    private func sessionCard(for session: WorkoutSession) -> some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(colorForPain(session.painLevel).opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text("\(Int(session.painLevel))")
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(colorForPain(session.painLevel))
                )

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(session.date, style: .date)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(AppColors.primaryText)
                Text("\(Int(session.duration / 60)) minutes")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)
                if !session.exercisesPerformed.isEmpty {
                    Text(session.exercisesPerformed.joined(separator: ", "))
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.success)
        }
        .cardStyle()
    }

    private func colorForPain(_ level: Double) -> Color {
        switch Int(level) {
        case 0...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
        }
    }

    private var savedConfirmationOverlay: some View {
        CelebrationOverlay(
            icon: "checkmark.circle.fill",
            message: "Session Saved!",
            iconColor: AppColors.success
        )
    }
}
