import SwiftUI

struct PainDetailView: View {
    @ObservedObject var viewModel: InjuryAnalysisViewModel

    // MARK: - Pain Assessment State
    @State var painTypes: [String] = []
    @State var painIntensity: Double = 5
    @State var painDurations: [String] = []
    @State var painFrequencies: [String] = []
    @State var painOnsets: [String] = []
    @State var aggravatingFactors: [String] = []
    @State var relievingFactors: [String] = []
    @State var additionalNotes: String = ""

    // MARK: - Wizard State
    @State private var currentStep: Int = 0
    @State private var isNavigatingBack: Bool = false
    @State var showApplyToAllConfirmation: Bool = false

    // MARK: - Custom Entry Popup
    private enum CustomField: Identifiable {
        case painType, frequency, onset, aggravating, relieving
        var id: Self { self }
    }
    @State private var activeCustomField: CustomField? = nil
    @State private var customInputText: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            AssessmentGrowthBackground(step: currentStep)

            VStack(spacing: 0) {
                wizardHeader
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.sm)

                ZStack {
                    currentStepView
                        .id(currentStep)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.35), value: currentStep)
            }

            wizardNavigationBar
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CoilWordmark()
            }
        }
        .coilNavBar()
        .onAppear {
            if viewModel.currentRegionIndex == 0 {
                AnalyticsService.shared.log(.assessmentStarted)
            }
            restoreFormState()
        }
        .onDisappear {
            if !viewModel.showAnalyzingScreen && !viewModel.isAnalyzing {
                viewModel.resetAnalysisState()
            }
        }
        .navigationDestination(isPresented: $viewModel.showAnalyzingScreen) {
            AnalyzingView(viewModel: viewModel)
        }
        .trackScreen("PainDetail")
        .alert("Apply to All Regions?", isPresented: $showApplyToAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Apply to All") {
                guard let assessment = buildAssessment() else { return }
                viewModel.applyToAllRegionsAndAnalyze(assessment)
            }
        } message: {
            Text("This will copy your current pain details to all \(viewModel.totalRegions) selected regions and start analysis.")
        }
        .alert(customFieldTitle, isPresented: Binding(
            get: { activeCustomField != nil },
            set: { if !$0 { activeCustomField = nil } }
        )) {
            TextField(customFieldPlaceholder, text: $customInputText)
            Button("Add") { addCustomEntry() }
            Button("Cancel", role: .cancel) { activeCustomField = nil }
        }
        .onChange(of: viewModel.currentRegionIndex) { _, _ in
            restoreFormState()
            if isNavigatingBack {
                currentStep = 7
                isNavigatingBack = false
            } else {
                currentStep = 0
            }
        }
    }

    // MARK: - Wizard Header

    private var wizardHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(alignment: .center) {
                if viewModel.hasMultipleRegions {
                    Text("Region \(viewModel.currentRegionIndex + 1) of \(viewModel.totalRegions)")
                        .font(AppFonts.captionSemiBold)
                        .foregroundColor(AppColors.ctaText)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.accent)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("\(currentStep + 1) / 8")
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(AppColors.secondaryText)
                    .accessibilityIdentifier("painDetail.stepIndicator")
            }

            if viewModel.hasMultipleRegions && viewModel.currentRegionIndex == 0 {
                // Surface the "apply to all regions" shortcut up front so symmetrical
                // multi-region users know they won't have to re-answer every area —
                // the actionable "Apply to All" button lives on the summary step (audit #15).
                Label("Similar pain in all \(viewModel.totalRegions) areas? You can apply these answers to all of them at the summary.", systemImage: "square.on.square")
                    .font(AppFonts.micro)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.elevatedSurface)
                        .frame(height: 4)
                    Capsule()
                        .fill(AppColors.accent)
                        .frame(width: geo.size.width * CGFloat(currentStep + 1) / 8.0, height: 4)
                        .animation(AppAnimations.smooth, value: currentStep)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Wizard Navigation Bar

    private var wizardNavigationBar: some View {
        VStack(spacing: AppSpacing.xs) {
            if currentStep < 7 {
                Button(action: handleContinue) {
                    Text("Continue")
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: !canContinue))
                .disabled(!canContinue)
                .accessibilityIdentifier("painDetail.continueButton")
            } else {
                if viewModel.isLastRegion {
                    Button(action: {
                        guard let assessment = buildAssessment() else { return }
                        viewModel.saveAndAnalyze(assessment)
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "sparkles")
                            Text("Review & Analyze")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("painDetail.analyzeButton")
                } else {
                    Button(action: {
                        guard let assessment = buildAssessment() else { return }
                        viewModel.saveAndAdvance(assessment)
                        currentStep = 0
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Text("Next Region")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }

            if currentStep > 0 || !viewModel.isFirstRegion {
                Button(action: handleBack) {
                    Text("Back")
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                }
                .accessibilityIdentifier("painDetail.backButton")
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.lg)
        .background(.ultraThinMaterial)
    }

    // MARK: - Current Step View

    @ViewBuilder
    var currentStepView: some View {
        switch currentStep {
        case 0: painTypeStepView
        case 1: intensityStepView
        case 2: durationStepView
        case 3: frequencyStepView
        case 4: onsetStepView
        case 5: aggravatingStepView
        case 6: relievingStepView
        default: summaryStepView
        }
    }

    // MARK: - Continue Validation

    private var canContinue: Bool {
        switch currentStep {
        case 0: return !painTypes.isEmpty
        case 1: return true
        case 2: return !painDurations.isEmpty
        case 3: return !painFrequencies.isEmpty
        case 4: return !painOnsets.isEmpty
        case 5: return !aggravatingFactors.isEmpty
        case 6: return !relievingFactors.isEmpty
        default: return true
        }
    }

    // MARK: - Navigation Handlers

    private func handleBack() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if currentStep > 0 {
            currentStep -= 1
        } else {
            isNavigatingBack = true
            guard let assessment = buildAssessment() else { return }
            viewModel.saveAndGoBack(assessment)
        }
    }

    func handleContinue() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        currentStep += 1
    }

    /// Advance after a short delay, but only if the wizard is still on the step the
    /// tap came from.
    ///
    /// The duration card auto-advances on a 0.25s delay, and `handleContinue`
    /// increments unconditionally, so two actions inside that window — double-tapping
    /// a card, or tapping a card and then the Continue button that enables
    /// immediately — each advanced a step and the next question was skipped
    /// entirely. Capturing the step here keeps `currentStep` private to this view
    /// while making the stale advance a no-op.
    func scheduleAutoAdvance(after delay: TimeInterval = 0.25) {
        let stepAtTap = currentStep
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard currentStep == stepAtTap else { return }
            handleContinue()
        }
    }

    // MARK: - Form State Management

    private func buildAssessment() -> PainAssessment? {
        guard let region = viewModel.currentRegion else { return nil }
        let trimmedNotes = additionalNotes.trimmingCharacters(in: .whitespaces)
        return PainAssessment(
            id: UUID(),
            selectedRegion: region,
            painTypes: painTypes,
            customPainDescription: nil,
            painIntensity: Int(painIntensity),
            painDurations: painDurations,
            painFrequencies: painFrequencies,
            painOnsets: painOnsets,
            aggravatingFactors: aggravatingFactors,
            relievingFactors: relievingFactors,
            additionalNotes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            currentTreatment: nil
        )
    }

    private func restoreFormState() {
        if let saved = viewModel.currentAssessment {
            painTypes = saved.painTypes
            painIntensity = Double(saved.painIntensity)
            painDurations = saved.painDurations
            painFrequencies = saved.painFrequencies
            painOnsets = saved.painOnsets
            aggravatingFactors = saved.aggravatingFactors
            relievingFactors = saved.relievingFactors
            additionalNotes = saved.additionalNotes ?? ""
        } else {
            painTypes = []
            painIntensity = 5
            painDurations = []
            painFrequencies = []
            painOnsets = []
            aggravatingFactors = []
            relievingFactors = []
            additionalNotes = ""
        }
    }

    // MARK: - Custom Entry Popup Helpers

    private var customFieldTitle: String {
        switch activeCustomField {
        case .painType:    return "Add Pain Type"
        case .frequency:   return "Add Frequency"
        case .onset:       return "Add Onset"
        case .aggravating: return "Add Aggravating Factor"
        case .relieving:   return "Add Relieving Factor"
        case nil:          return "Add your own"
        }
    }

    private var customFieldPlaceholder: String {
        switch activeCustomField {
        case .painType:    return "e.g., Shooting, Pressure..."
        case .frequency:   return "e.g., After meals, Mornings..."
        case .onset:       return "e.g., After sleeping..."
        case .aggravating: return "e.g., Cold weather, Stress..."
        case .relieving:   return "e.g., Hot bath, Elevation..."
        case nil:          return "Describe..."
        }
    }

    private func addCustomEntry() {
        let trimmed = customInputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch activeCustomField {
        case .painType:
            if !painTypes.contains(trimmed) { painTypes.append(trimmed) }
        case .frequency:
            if !painFrequencies.contains(trimmed) { painFrequencies.append(trimmed) }
        case .onset:
            if !painOnsets.contains(trimmed) { painOnsets.append(trimmed) }
        case .aggravating:
            if !aggravatingFactors.contains(trimmed) { aggravatingFactors.append(trimmed) }
        case .relieving:
            if !relievingFactors.contains(trimmed) { relievingFactors.append(trimmed) }
        case nil:
            break
        }
        customInputText = ""
        activeCustomField = nil
    }

    // MARK: - Add More Button (dashed card)

    @ViewBuilder
    private func addCustomButton(field: CustomField) -> some View {
        Button(action: {
            customInputText = ""
            activeCustomField = field
        }) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 28)
                Text("Add your own")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md + 2)
            .background(
                RoundedRectangle(cornerRadius: AppCorners.medium)
                    .strokeBorder(AppColors.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
            // .plain buttons only hit-test rendered pixels — the dashed border has
            // no fill, so without an explicit content shape the row interior is dead.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pain Type (multi-select cards + custom)

    private var painTypeOptions: [String] {
        PainAssessment.PainType.allCases.map { $0.displayName }
    }

    private var customPainTypeEntries: [String] {
        painTypes.filter { !painTypeOptions.contains($0) }
    }

    var painTypeSelection: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(painTypeOptions, id: \.self) { type in
                optionCard(
                    label: type,
                    isSelected: painTypes.contains(type),
                    action: {
                        if painTypes.contains(type) {
                            painTypes.removeAll { $0 == type }
                        } else {
                            painTypes.append(type)
                        }
                    }
                )
            }
            ForEach(customPainTypeEntries, id: \.self) { entry in
                optionCard(label: entry, isSelected: true) {
                    painTypes.removeAll { $0 == entry }
                }
            }
            addCustomButton(field: .painType)
        }
    }

    // MARK: - Pain Intensity

    var painIntensitySlider: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("\(Int(painIntensity))")
                    .font(AppFonts.display)
                    .foregroundColor(painColor)
                Text("/ 10")
                    .font(AppFonts.sectionTitle)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                Text(painDescription)
                    .font(AppFonts.bodySemiBold)
                    .foregroundColor(painColor)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(painColor.opacity(0.12))
                    .cornerRadius(AppCorners.medium)
            }
            Slider(value: $painIntensity, in: 1...10, step: 1)
                .tint(painColor)
                .padding(.vertical, AppSpacing.sm)
            HStack {
                Text("Mild")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                Text("Severe")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(AppSpacing.xl)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.elevatedSurface, lineWidth: 1.5)
        )
    }

    // MARK: - Pain Duration (single-select cards)

    var painDurationOptions: [String] {
        PainAssessment.PainDuration.allCases.map { $0.displayName }
    }

    var painDurationPicker: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(painDurationOptions, id: \.self) { duration in
                optionCard(
                    label: duration,
                    isSelected: painDurations.contains(duration),
                    action: {
                        if painDurations.contains(duration) {
                            painDurations = []
                        } else {
                            painDurations = [duration]
                        }
                    }
                )
            }
        }
    }

    // MARK: - Pain Frequency (multi-select cards + custom)

    private var painFrequencyOptions: [String] {
        PainAssessment.PainFrequency.allCases.map { $0.displayName }
    }

    private var customFrequencyEntries: [String] {
        painFrequencies.filter { !painFrequencyOptions.contains($0) }
    }

    var painFrequencyPicker: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(painFrequencyOptions, id: \.self) { frequency in
                optionCard(
                    label: frequency,
                    isSelected: painFrequencies.contains(frequency),
                    action: {
                        if painFrequencies.contains(frequency) {
                            painFrequencies.removeAll { $0 == frequency }
                        } else {
                            painFrequencies.append(frequency)
                        }
                    }
                )
            }
            ForEach(customFrequencyEntries, id: \.self) { entry in
                optionCard(label: entry, isSelected: true) {
                    painFrequencies.removeAll { $0 == entry }
                }
            }
            addCustomButton(field: .frequency)
        }
    }

    // MARK: - Pain Onset (multi-select cards + custom)

    private var painOnsetOptions: [String] {
        PainAssessment.PainOnset.allCases.map { $0.displayName }
    }

    private var customOnsetEntries: [String] {
        painOnsets.filter { !painOnsetOptions.contains($0) }
    }

    var painOnsetPicker: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(painOnsetOptions, id: \.self) { onset in
                optionCard(
                    label: onset,
                    isSelected: painOnsets.contains(onset),
                    action: {
                        if painOnsets.contains(onset) {
                            painOnsets.removeAll { $0 == onset }
                        } else {
                            painOnsets.append(onset)
                        }
                    }
                )
            }
            ForEach(customOnsetEntries, id: \.self) { entry in
                optionCard(label: entry, isSelected: true) {
                    painOnsets.removeAll { $0 == entry }
                }
            }
            addCustomButton(field: .onset)
        }
    }

    // MARK: - Aggravating Factors (multi-select cards + custom)

    var aggravatingFactorsSelection: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(aggravatingOptions, id: \.self) { factor in
                optionCard(
                    label: factor,
                    isSelected: aggravatingFactors.contains(factor),
                    action: {
                        if aggravatingFactors.contains(factor) {
                            aggravatingFactors.removeAll { $0 == factor }
                        } else {
                            aggravatingFactors.append(factor)
                        }
                    }
                )
            }
            ForEach(customAggravatingEntries, id: \.self) { factor in
                optionCard(label: factor, isSelected: true) {
                    aggravatingFactors.removeAll { $0 == factor }
                }
            }
            addCustomButton(field: .aggravating)
        }
    }

    // MARK: - Relieving Factors (multi-select cards + custom)

    var relievingFactorsSelection: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(relievingOptions, id: \.self) { factor in
                optionCard(
                    label: factor,
                    isSelected: relievingFactors.contains(factor),
                    action: {
                        if relievingFactors.contains(factor) {
                            relievingFactors.removeAll { $0 == factor }
                        } else {
                            relievingFactors.append(factor)
                        }
                    }
                )
            }
            ForEach(customRelievingEntries, id: \.self) { factor in
                optionCard(label: factor, isSelected: true) {
                    relievingFactors.removeAll { $0 == factor }
                }
            }
            addCustomButton(field: .relieving)
        }
    }

    // MARK: - Custom Factor Helpers

    var customAggravatingEntries: [String] {
        aggravatingFactors.filter { !aggravatingOptions.contains($0) }
    }

    var customRelievingEntries: [String] {
        relievingFactors.filter { !relievingOptions.contains($0) }
    }

    // MARK: - Region-Specific Factor Options

    var aggravatingOptions: [String] {
        guard let region = viewModel.currentRegion else {
            return ["Walking", "Sitting", "Lifting", "Running"]
        }
        switch region.zoneKey {
        case "head":
            return ["Looking at screens", "Bright lights", "Stress/tension", "Lack of sleep", "Bending forward", "Physical exertion", "Concentrating"]
        case "neck":
            return ["Turning head", "Looking up", "Looking down", "Sitting at desk", "Driving", "Sleeping position", "Stress/tension"]
        case "chest":
            return ["Deep breathing", "Coughing", "Pushing", "Lifting", "Reaching forward", "Lying flat", "Twisting torso"]
        case "abdomen":
            return ["Bending forward", "Coughing", "Lifting", "Sitting up", "Eating", "Twisting", "Standing long"]
        case "left_shoulder", "right_shoulder":
            return ["Reaching overhead", "Reaching behind back", "Throwing", "Pushing", "Pulling", "Sleeping on side", "Carrying bags", "Lifting"]
        case "left_upper_arm", "right_upper_arm":
            return ["Lifting", "Pushing", "Pulling", "Carrying", "Reaching overhead", "Throwing", "Push-ups"]
        case "left_elbow", "right_elbow":
            return ["Gripping", "Twisting forearm", "Lifting objects", "Typing", "Opening jars", "Pushing", "Pulling"]
        case "left_forearm", "right_forearm":
            return ["Gripping", "Twisting forearm", "Typing", "Writing", "Lifting", "Using tools", "Opening jars"]
        case "left_wrist_hand", "right_wrist_hand":
            return ["Gripping", "Typing", "Writing", "Twisting motion", "Pushing up", "Carrying", "Opening jars", "Using phone"]
        case "upper_back":
            return ["Sitting at desk", "Slouching", "Deep breathing", "Twisting", "Lifting overhead", "Reaching forward", "Driving"]
        case "lower_back":
            return ["Bending forward", "Lifting", "Sitting long", "Standing long", "Twisting", "Getting out of bed", "Walking", "Coughing/sneezing"]
        case "left_glute", "right_glute":
            return ["Sitting long", "Walking uphill", "Climbing stairs", "Running", "Squatting", "Lunging", "Standing from chair"]
        case "left_hip", "right_hip":
            return ["Walking", "Climbing stairs", "Sitting long", "Standing from chair", "Crossing legs", "Running", "Squatting", "Lying on side"]
        case "left_thigh", "right_thigh":
            return ["Walking", "Running", "Squatting", "Climbing stairs", "Kicking", "Lunging", "Stretching", "Sitting long"]
        case "left_hamstring", "right_hamstring":
            return ["Running", "Sprinting", "Bending forward", "Stretching", "Kicking", "Climbing stairs", "Sitting long"]
        case "left_knee", "right_knee":
            return ["Walking", "Climbing stairs", "Squatting", "Kneeling", "Running", "Jumping", "Going downstairs", "Sitting long"]
        case "left_calf_shin", "right_calf_shin":
            return ["Walking", "Running", "Jumping", "Climbing stairs", "Standing long", "Pointing toes", "Pushing off"]
        case "left_ankle_foot", "right_ankle_foot":
            return ["Walking", "Running", "Standing long", "Going up stairs", "Uneven surfaces", "Wearing shoes", "First steps in morning"]
        default:
            return ["Walking", "Sitting", "Lifting", "Running", "Twisting", "Standing long"]
        }
    }

    var relievingOptions: [String] {
        guard let region = viewModel.currentRegion else {
            return ["Rest", "Ice", "Heat", "Stretching", "Medication"]
        }
        switch region.zoneKey {
        case "head":
            return ["Rest", "Quiet dark room", "Medication", "Cold compress", "Hydration", "Sleep", "Reducing screen time"]
        case "neck":
            return ["Rest", "Heat", "Gentle stretching", "Massage", "Medication", "Posture correction", "Neck support pillow"]
        case "chest":
            return ["Rest", "Ice", "Heat", "Medication", "Upright position", "Gentle breathing exercises"]
        case "abdomen":
            return ["Rest", "Heat", "Lying down", "Medication", "Gentle movement", "Avoiding triggers"]
        case "left_shoulder", "right_shoulder":
            return ["Rest", "Ice", "Heat", "Gentle stretching", "Arm support/sling", "Medication", "Avoiding overhead reach"]
        case "left_upper_arm", "right_upper_arm":
            return ["Rest", "Ice", "Heat", "Gentle stretching", "Medication", "Compression", "Avoiding lifting"]
        case "left_elbow", "right_elbow":
            return ["Rest", "Ice", "Brace/strap", "Stretching forearm", "Medication", "Avoiding gripping"]
        case "left_forearm", "right_forearm":
            return ["Rest", "Ice", "Stretching", "Forearm brace", "Medication", "Ergonomic adjustments", "Avoiding repetitive motion"]
        case "left_wrist_hand", "right_wrist_hand":
            return ["Rest", "Ice", "Wrist brace/splint", "Stretching", "Medication", "Elevation", "Ergonomic adjustments"]
        case "upper_back":
            return ["Rest", "Heat", "Stretching", "Posture correction", "Massage", "Medication", "Foam rolling"]
        case "lower_back":
            return ["Rest", "Ice", "Heat", "Gentle stretching", "Walking short", "Medication", "Lying with knees bent", "Lumbar support"]
        case "left_glute", "right_glute":
            return ["Rest", "Heat", "Stretching", "Foam rolling", "Massage", "Medication", "Gentle walking"]
        case "left_hip", "right_hip":
            return ["Rest", "Ice", "Heat", "Stretching", "Gentle walking", "Medication", "Avoiding sitting long"]
        case "left_thigh", "right_thigh":
            return ["Rest", "Ice", "Compression", "Stretching", "Foam rolling", "Medication", "Gentle walking"]
        case "left_hamstring", "right_hamstring":
            return ["Rest", "Ice", "Gentle stretching", "Compression", "Foam rolling", "Medication", "Gentle walking"]
        case "left_knee", "right_knee":
            return ["Rest", "Ice", "Elevation", "Compression wrap", "Stretching", "Medication", "Knee brace", "Avoiding stairs"]
        case "left_calf_shin", "right_calf_shin":
            return ["Rest", "Ice", "Elevation", "Compression", "Stretching calves", "Foam rolling", "Medication", "Massage"]
        case "left_ankle_foot", "right_ankle_foot":
            return ["Rest", "Ice", "Elevation", "Compression wrap", "Supportive shoes", "Medication", "Ankle brace", "Stretching calves"]
        default:
            return ["Rest", "Ice", "Heat", "Stretching", "Medication", "Elevation"]
        }
    }

    // MARK: - Helpers

    var painColor: Color {
        switch Int(painIntensity) {
        case 1...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
        }
    }

    var painDescription: String {
        switch Int(painIntensity) {
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        case 7...8: return "Severe"
        default: return "Extreme"
        }
    }
}
