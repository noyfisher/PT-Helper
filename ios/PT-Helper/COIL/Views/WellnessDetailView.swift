import SwiftUI

enum WellnessDestination: Hashable {
    case result
    case emergency(warnings: [String])
}

struct WellnessDetailView: View {
    @ObservedObject var viewModel: WellnessAnalysisViewModel

    // MARK: - Form State

    @State private var impactLevel: WellnessAssessment.ImpactLevel = .moderate
    @State private var motivationLevel: Double = 7
    @State private var duration: WellnessAssessment.Duration = .fewMonths
    @State private var selectedTimeOfDay: Set<WellnessAssessment.TimeOfDay> = []
    @State private var commitmentLevel: WellnessAssessment.CommitmentLevel = .fifteenMin
    @State private var selectedActivities: [String] = []
    @State private var customActivityText: String = ""
    @State private var selectedHabits: [String] = []
    @State private var customHabitText: String = ""
    @State private var selectedPriorAttempts: Set<WellnessAssessment.PriorAttempt> = []
    @State private var specificContext: String = ""
    @State private var additionalNotes: String = ""

    @State private var destination: WellnessDestination?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            if viewModel.showAnalyzingScreen {
                WellnessAnalyzingView(viewModel: viewModel)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: AppSpacing.xl) {
                            progressHeader
                                .id("top")

                            impactLevelSection
                            motivationSection
                            durationSection
                            timeOfDaySection
                            commitmentSection
                            activitiesAffectedSection
                            currentHabitsSection
                            priorAttemptsSection
                            contextSection

                            navigationButtons
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.md)
                    }
                    .onChange(of: viewModel.currentGoalIndex) { _, _ in
                        restoreFormState()
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.currentGoal?.category.displayName ?? "Goal Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $destination) { dest in
            switch dest {
            case .result:
                WellnessResultView(viewModel: viewModel)
            case .emergency(let warnings):
                EmergencyRedirectView(warningMessages: warnings) {
                    destination = nil
                    viewModel.resetAnalysisState()
                }
            }
        }
        .onChange(of: destination) { _, newValue in
            // Popping back from the results screen must also tear down the
            // analyzing screen. startAnalysis sets showAnalyzingScreen = true and
            // the success path never clears it, so returning here re-rendered
            // WellnessAnalyzingView with no work in flight: a spinner that never
            // resolves, with the back button hidden, no Cancel (it only shows
            // while isAnalyzing), and the cover's X living on the stack root —
            // force-quit was the only way out, on the ordinary happy path of
            // every wellness assessment.
            //
            // Ported verbatim from AnalyzingView, INCLUDING the Task/yield/sleep
            // ordering: mutating a second navigation binding inside the same
            // transaction crashes with a simultaneous-state-mutation error.
            if newValue == nil {
                viewModel.analysisResult = nil
                Task { @MainActor in
                    await Task.yield()
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(50))
                    viewModel.showAnalyzingScreen = false
                }
            }
        }
        .onAppear { restoreFormState() }
        .onChange(of: viewModel.analysisResult?.id) { _, newValue in
            if newValue != nil { destination = .result }
        }
        .onChange(of: viewModel.emergencyMessages) { _, newValue in
            if let warnings = newValue { destination = .emergency(warnings: warnings) }
        }
        .trackScreen("WellnessDetail")
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            if viewModel.hasMultipleGoals {
                Text("Goal \(viewModel.currentGoalIndex + 1) of \(viewModel.totalGoals)")
                    .font(AppFonts.captionMedium)
                    .foregroundColor(Color.white.opacity(0.7))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 3)
                        Capsule()
                            .fill(AppColors.accent)
                            .frame(width: geo.size.width * CGFloat(viewModel.currentGoalIndex + 1) / CGFloat(viewModel.totalGoals), height: 3)
                            .animation(AppAnimations.smooth, value: viewModel.currentGoalIndex)
                    }
                }
                .frame(height: 3)
            }

            if let goal = viewModel.currentGoal {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: goal.category.icon)
                        .foregroundColor(goal.category.color)
                    Text("Tell us more about: \(goal.category.displayName)")
                        .font(AppFonts.smallMedium)
                        .foregroundColor(.white)
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity)
                .background(goal.category.color.opacity(0.1))
                .cornerRadius(AppCorners.medium)
            }
        }
    }

    // MARK: - Impact Level

    private var impactLevelSection: some View {
        CardSection(icon: "gauge.medium", color: AppColors.warning, title: "How much does this affect your daily life?") {
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(WellnessAssessment.ImpactLevel.allCases, id: \.self) { level in
                    ChipButton(
                        label: level.displayName,
                        isSelected: impactLevel == level,
                        action: { impactLevel = level }
                    )
                }
            }
        }
    }

    // MARK: - Motivation Slider

    private var motivationSection: some View {
        CardSection(icon: "flame.fill", color: Color(CoilPalette.pop), title: "How motivated are you to improve this?") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text("\(Int(motivationLevel))")
                        .font(AppFonts.statNumber)
                        .foregroundColor(motivationColor)
                    Text("/ 10")
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Text(motivationDescription)
                        .font(AppFonts.captionMedium)
                        .foregroundColor(motivationColor)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(motivationColor.opacity(0.12))
                        .cornerRadius(AppCorners.small)
                }
                Slider(value: $motivationLevel, in: 1...10, step: 1)
                    .tint(motivationColor)
                HStack {
                    Text("Low").font(AppFonts.micro).foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Text("Very High").font(AppFonts.micro).foregroundColor(AppColors.secondaryText)
                }
            }
        }
    }

    private var motivationColor: Color {
        switch Int(motivationLevel) {
        case 1...3: return AppColors.danger
        case 4...6: return AppColors.warning
        default: return AppColors.success
        }
    }

    private var motivationDescription: String {
        switch Int(motivationLevel) {
        case 1...3: return "Getting started"
        case 4...6: return "Motivated"
        case 7...8: return "Very motivated"
        default: return "All in!"
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        CardSection(icon: "calendar", color: AppColors.accent, title: "How long has this been an issue?") {
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(WellnessAssessment.Duration.allCases, id: \.self) { d in
                    ChipButton(
                        label: d.displayName,
                        isSelected: duration == d,
                        action: { duration = d }
                    )
                }
            }
        }
    }

    // MARK: - Time of Day (Multi-select)

    private var timeOfDaySection: some View {
        CardSection(icon: "clock.fill", color: AppColors.accent, title: "When does this bother you most?") {
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(WellnessAssessment.TimeOfDay.allCases, id: \.self) { time in
                    ChipButton(
                        label: time.displayName,
                        isSelected: selectedTimeOfDay.contains(time),
                        action: {
                            if selectedTimeOfDay.contains(time) {
                                selectedTimeOfDay.remove(time)
                            } else {
                                selectedTimeOfDay.insert(time)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Commitment Level

    private var commitmentSection: some View {
        CardSection(icon: "timer", color: AppColors.accent, title: "How much time can you dedicate daily?") {
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(WellnessAssessment.CommitmentLevel.allCases, id: \.self) { level in
                    ChipButton(
                        label: level.displayName,
                        isSelected: commitmentLevel == level,
                        action: { commitmentLevel = level }
                    )
                }
            }
        }
    }

    // MARK: - Activities Affected (Goal-specific + custom)

    private var activitiesAffectedSection: some View {
        CardSection(icon: "figure.walk", color: AppColors.accent, title: "Daily activities affected") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(dailyActivitiesOptions, id: \.self) { activity in
                        ChipButton(
                            label: activity,
                            isSelected: selectedActivities.contains(activity),
                            action: {
                                if selectedActivities.contains(activity) {
                                    selectedActivities.removeAll { $0 == activity }
                                } else {
                                    selectedActivities.append(activity)
                                }
                            }
                        )
                    }
                }
                // Custom entry
                HStack(spacing: AppSpacing.sm) {
                    TextField("Add your own...", text: $customActivityText)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.inputBackground)
                        .cornerRadius(AppCorners.small)
                        .submitLabel(.done)
                        .onSubmit { addCustomActivity() }
                    Button(action: addCustomActivity) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(AppColors.accent)
                    }
                    .disabled(customActivityText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add custom activity")
                }
            }
        }
    }

    private func addCustomActivity() {
        let trimmed = customActivityText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !selectedActivities.contains(trimmed) else { return }
        selectedActivities.append(trimmed)
        customActivityText = ""
    }

    // MARK: - Current Habits (Goal-specific + custom)

    private var currentHabitsSection: some View {
        CardSection(icon: "heart.fill", color: AppColors.success, title: "What do you currently do that helps?") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(currentHabitsOptions, id: \.self) { habit in
                        ChipButton(
                            label: habit,
                            isSelected: selectedHabits.contains(habit),
                            action: {
                                if selectedHabits.contains(habit) {
                                    selectedHabits.removeAll { $0 == habit }
                                } else {
                                    selectedHabits.append(habit)
                                }
                            }
                        )
                    }
                }
                HStack(spacing: AppSpacing.sm) {
                    TextField("Add your own...", text: $customHabitText)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.inputBackground)
                        .cornerRadius(AppCorners.small)
                        .submitLabel(.done)
                        .onSubmit { addCustomHabit() }
                    Button(action: addCustomHabit) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(AppColors.accent)
                    }
                    .disabled(customHabitText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add custom habit")
                }
            }
        }
    }

    private func addCustomHabit() {
        let trimmed = customHabitText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !selectedHabits.contains(trimmed) else { return }
        selectedHabits.append(trimmed)
        customHabitText = ""
    }

    // MARK: - Prior Attempts

    private var priorAttemptsSection: some View {
        CardSection(icon: "arrow.counterclockwise", color: AppColors.accent, title: "What have you tried before?") {
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(WellnessAssessment.PriorAttempt.allCases, id: \.self) { attempt in
                    ChipButton(
                        label: attempt.displayName,
                        isSelected: selectedPriorAttempts.contains(attempt),
                        action: {
                            if selectedPriorAttempts.contains(attempt) {
                                selectedPriorAttempts.remove(attempt)
                            } else {
                                selectedPriorAttempts.insert(attempt)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Context (Free text)

    private var contextSection: some View {
        CardSection(icon: "text.alignleft", color: AppColors.accent, title: "Tell us more about your situation") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(AppColors.accent)
                    Text("AI-powered")
                        .font(AppFonts.microMedium)
                        .foregroundColor(AppColors.accentText)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.accentTint)
                .cornerRadius(AppCorners.small)

                Text("What does a typical day look like? What would improvement mean for you? The more detail you provide, the better your personalized plan will be.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)

                TextField("Share your story...", text: $specificContext, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(AppSpacing.md)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.small)
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                if !viewModel.isFirstGoal {
                    Button(action: {
                        if let assessment = buildAssessment() {
                            viewModel.saveAndGoBack(assessment)
                        }
                    }) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if viewModel.isLastGoal {
                    Button(action: {
                        if let assessment = buildAssessment() {
                            viewModel.saveAndAnalyze(assessment)
                        }
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "sparkles")
                            Text("Review & Analyze")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("wellnessDetail.analyzeButton")
                } else {
                    Button(action: {
                        if let assessment = buildAssessment() {
                            viewModel.saveAndAdvance(assessment)
                        }
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Text("Next Goal")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(.bottom, AppSpacing.xxl)
    }

    // MARK: - Build Assessment

    private func buildAssessment() -> WellnessAssessment? {
        guard let goal = viewModel.currentGoal else { return nil }
        return WellnessAssessment(
            id: UUID(),
            goalCategory: goal.category,
            customGoalText: goal.customDescription,
            impactLevel: impactLevel,
            motivationLevel: Int(motivationLevel),
            duration: duration,
            timeOfDay: Array(selectedTimeOfDay),
            dailyActivitiesAffected: selectedActivities,
            currentHabits: selectedHabits,
            priorAttempts: Array(selectedPriorAttempts),
            commitmentLevel: commitmentLevel,
            specificContext: specificContext.isEmpty ? nil : specificContext,
            additionalNotes: additionalNotes.isEmpty ? nil : additionalNotes
        )
    }

    // MARK: - Restore Form State

    private func restoreFormState() {
        if let saved = viewModel.currentAssessment {
            impactLevel = saved.impactLevel
            motivationLevel = Double(saved.motivationLevel)
            duration = saved.duration
            selectedTimeOfDay = Set(saved.timeOfDay)
            commitmentLevel = saved.commitmentLevel
            selectedActivities = saved.dailyActivitiesAffected
            selectedHabits = saved.currentHabits
            selectedPriorAttempts = Set(saved.priorAttempts)
            specificContext = saved.specificContext ?? ""
            additionalNotes = saved.additionalNotes ?? ""
        } else {
            impactLevel = .moderate
            motivationLevel = 7
            duration = .fewMonths
            selectedTimeOfDay = []
            commitmentLevel = .fifteenMin
            selectedActivities = []
            selectedHabits = []
            selectedPriorAttempts = []
            specificContext = ""
            additionalNotes = ""
        }
    }

    // MARK: - Goal-Specific Options

    private var dailyActivitiesOptions: [String] {
        guard let goal = viewModel.currentGoal else {
            return ["Daily activities", "Work tasks", "Sleep quality", "Physical comfort", "Energy levels", "Mobility", "Strength", "Overall wellbeing"]
        }
        switch goal.category {
        case .improveSleep:
            return ["Falling asleep", "Staying asleep", "Waking up tired", "Restless legs", "Back pain in bed", "Neck pain in bed", "Racing thoughts", "Screen time before bed"]
        case .improvePosture:
            return ["Desk work", "Phone use", "Driving", "Standing", "Walking", "Slouching", "Rounded shoulders", "Forward head", "Lower back curve"]
        case .standLonger:
            return ["Retail/service work", "Standing desk", "Cooking", "Events/concerts", "Commuting", "Foot pain", "Lower back fatigue", "Leg fatigue"]
        case .sitWithoutPain:
            return ["Office chair", "Car seat", "Couch", "Dining chair", "Airplane seat", "Lower back pain", "Hip tightness", "Tailbone pressure", "Numbness/tingling"]
        case .workWithEquipment:
            return ["Lifting heavy objects", "Repetitive motions", "Overhead reaching", "Bending/stooping", "Carrying loads", "Using power tools", "Gripping", "Pushing/pulling"]
        case .driveWithoutPain:
            return ["Short commute (<30 min)", "Long commute (30-60 min)", "Road trips (1+ hours)", "Lower back stiffness", "Neck tension", "Hip tightness", "Shoulder fatigue", "Leg cramping"]
        case .reduceMorningStiffness:
            return ["Getting out of bed", "First steps", "Bending over", "Reaching overhead", "Neck rotation", "Back flexibility", "Joint stiffness", "Takes 30+ min to loosen up"]
        case .coreAndBalance:
            return ["Standing on one foot", "Walking on uneven ground", "Getting up from floor", "Carrying groceries", "Climbing stairs", "Feeling unsteady", "Weak core", "Lower back instability"]
        case .flexibilityAndMobility:
            return ["Touching toes", "Reaching behind back", "Squatting down", "Turning neck", "Shoulder range", "Hip rotation", "Ankle mobility", "Overall stiffness"]
        case .manageStress:
            return ["Shoulder tension", "Jaw clenching", "Headaches", "Shallow breathing", "Neck tightness", "Back tension", "Difficulty relaxing", "Poor sleep from stress"]
        case .stayActiveAsYouAge:
            return ["Joint stiffness", "Balance concerns", "Strength loss", "Flexibility loss", "Recovery takes longer", "Fear of falling", "Reduced endurance", "Want to stay independent"]
        case .fasterWorkoutRecovery:
            return ["Muscle soreness", "Joint stiffness after exercise", "Slow recovery between sessions", "Tightness during warmup", "Reduced performance", "Post-workout fatigue", "Specific muscle groups", "General body ache"]
        case .custom:
            return ["Daily activities", "Work tasks", "Sleep quality", "Physical comfort", "Energy levels", "Mobility", "Strength", "Overall wellbeing"]
        }
    }

    private var currentHabitsOptions: [String] {
        guard let goal = viewModel.currentGoal else {
            return ["Regular exercise", "Stretching", "Healthy diet", "Good sleep", "Stress management", "Professional help", "Self-care routine", "Mindfulness"]
        }
        switch goal.category {
        case .improveSleep:
            return ["Regular bedtime", "Dark room", "Cool temperature", "No screens before bed", "Reading", "Meditation", "White noise", "Stretching before bed"]
        case .improvePosture:
            return ["Posture reminders", "Standing desk", "Ergonomic chair", "Stretching breaks", "Yoga", "Core exercises", "Back brace", "Mindful sitting"]
        case .standLonger:
            return ["Supportive shoes", "Anti-fatigue mat", "Shifting weight", "Taking breaks", "Leg exercises", "Compression socks", "Stretching", "Walking breaks"]
        case .sitWithoutPain:
            return ["Lumbar support", "Standing breaks", "Seat cushion", "Stretching", "Core exercises", "Ergonomic setup", "Position changes", "Walking breaks"]
        case .workWithEquipment:
            return ["Proper lifting form", "Warm-up before work", "Supportive gear", "Rest breaks", "Stretching after", "Strength training", "Ergonomic tools", "Body mechanics awareness"]
        case .driveWithoutPain:
            return ["Lumbar support", "Seat adjustment", "Frequent stops", "Stretching at stops", "Heated seat", "Position changes", "Cruise control use", "Mirror adjustment"]
        case .reduceMorningStiffness:
            return ["Stretching in bed", "Hot shower", "Gentle movement", "Sleeping position changes", "New mattress/pillow", "Evening stretching", "Hydration", "Anti-inflammatory diet"]
        case .coreAndBalance:
            return ["Core exercises", "Balance practice", "Yoga", "Pilates", "Walking regularly", "Tai chi", "Stability ball", "Single-leg exercises"]
        case .flexibilityAndMobility:
            return ["Daily stretching", "Yoga", "Foam rolling", "Dynamic warmups", "Mobility drills", "Massage", "Hot baths", "Active recovery"]
        case .manageStress:
            return ["Deep breathing", "Meditation", "Exercise", "Walking", "Yoga", "Massage", "Journaling", "Time in nature"]
        case .stayActiveAsYouAge:
            return ["Regular walking", "Light exercise", "Stretching routine", "Social activities", "Balance practice", "Strength training", "Swimming", "Gardening"]
        case .fasterWorkoutRecovery:
            return ["Stretching after workout", "Foam rolling", "Cold therapy", "Hot therapy", "Protein intake", "Sleep priority", "Active recovery days", "Hydration"]
        case .custom:
            return ["Regular exercise", "Stretching", "Healthy diet", "Good sleep", "Stress management", "Professional help", "Self-care routine", "Mindfulness"]
        }
    }
}
