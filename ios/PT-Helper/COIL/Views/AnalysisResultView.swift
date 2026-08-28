import SwiftUI

struct AnalysisResultView: View {
    let analysisResult: AnalysisResult
    var validationWarnings: [ValidationWarning] = []
    var redFlagAlerts: [ValidationWarning] = []
    /// True when pushed from the Progress tab's "Your Last Analysis" card (D-6):
    /// hides plan generation + assessment-flow navigation and skips the store re-save.
    var isReadOnly: Bool = false
    @State private var showRehabPlan = false
    @State private var expandedConditions: Set<String> = []
    @State private var showConfidenceInfo = false
    @State private var showVerificationInfo = false
    /// Drives the staggered condition-card entrance (audit #78).
    @State private var cardsAppeared = false
    @State private var showPreferencesSheet = false
    @State private var showRiskAcknowledgement = false
    /// Set when the user taps Generate/Skip in the preferences sheet. Generation and the
    /// navigation push are deferred to the sheet's onDismiss — mutating the navigation
    /// destination (or publishing from rehabVM) in the same transaction as the sheet
    /// dismissal sends SwiftUI into an infinite layout loop that freezes the app.
    @State private var pendingPlanGeneration = false
    // NOTE: no @Environment(\.dismiss) here — this view registers a
    // navigationDestination, and reading dismiss alongside it causes the
    // infinite-render freeze documented in Components/DismissButton.swift.
    /// Prefetched rehab plan VM — generation starts as soon as this view appears
    @StateObject private var rehabVM = RehabPlanViewModel()

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Emergency / red-flag alerts stay pinned at the very top.
                    if !redFlagAlerts.isEmpty {
                        appRedFlagAlert
                    }
                    if !aiRedFlagMessages.isEmpty {
                        aiRedFlagAlert
                    }
                    // Lead with the answer the user waited for (audit #25).
                    overallSummaryCard
                    verificationBadge
                    ForEach(Array(displayedConditions.enumerated()), id: \.element.id) { index, condition in
                        conditionCard(for: condition)
                            // Reveal one at a time so the diagnosis feels considered,
                            // not dumped on the user (audit #78).
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 14)
                            .animation(AppAnimations.smooth.delay(Double(index) * 0.12), value: cardsAppeared)
                    }
                    // Standing disclaimer + validation cautions moved below the result.
                    if !cautionWarnings.isEmpty {
                        validationCautionBanner
                    }
                    disclaimerBanner
                    if !isReadOnly {
                        buildRehabPlanButton
                        navigationButtons
                    }
                }
                .padding(AppSpacing.xl)
            }
        }
        .navigationTitle("Analysis Results")
        .navigationDestination(isPresented: $showRehabPlan) {
            RehabPlanView(viewModel: rehabVM, analysisResult: analysisResult)
        }
        .sheet(isPresented: $showPreferencesSheet, onDismiss: {
            guard pendingPlanGeneration else { return }
            pendingPlanGeneration = false
            rehabVM.generateRehabPlan(from: analysisResult)
            showRehabPlan = true
        }) {
            rehabPreferencesSheet
        }
        .sheet(isPresented: $showRiskAcknowledgement) {
            RedFlagAcknowledgementSheet(
                analysisId: analysisResult.id.uuidString,
                warningMessages: redFlagAlerts.map(\.message) + aiRedFlagMessages,
                onAcknowledge: {
                    SeriousWarningAcknowledgements.acknowledge(planId: analysisResult.id.uuidString)
                    // Persist exactly what the sheet displayed. This previously
                    // recorded only the app-detected alerts, so condition-level
                    // warnings the user actually acknowledged were absent from the
                    // record — a gap in the acknowledgement trail.
                    RiskAcknowledgementRecorder.record(analysisId: analysisResult.id.uuidString,
                                                       warnings: redFlagAlerts.map(\.message) + aiRedFlagMessages)
                    showRiskAcknowledgement = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showPreferencesSheet = true
                    }
                },
                onDismiss: { showRiskAcknowledgement = false }
            )
        }
        .alert("About Match Strength", isPresented: $showConfidenceInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Match strength is capped at 85% because AI analysis should always be verified by a healthcare professional. A \"Strong\" match means your symptoms closely align with this condition.")
        }
        .alert("How we checked this", isPresented: $showVerificationInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Your results ran through a second AI pass that argues against the first answer to refine the top conditions, plus a multi-step safety screen (red-flag detection, anatomical relevance, and confidence calibration). It's a coaching aid, not a diagnosis — always verify with a clinician.")
        }
        .trackScreen("AnalysisResult")
        .onAppear {
            if !isReadOnly { AnalysisResultStore.shared.save(analysisResult) }
            cardsAppeared = true
        }
    }

    // MARK: - Filtered Warnings

    /// Caution-level warnings from validation (not red flags)
    private var cautionWarnings: [ValidationWarning] {
        validationWarnings.filter { $0.severity == .caution }
    }

    // MARK: - Disclaimer

    private var disclaimerBanner: some View {
        HStack(spacing: AppSpacing.comfortable) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(AppColors.accent)
            Text(analysisResult.disclaimerText)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding()
        .background(AppColors.accentTint)
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Validation Caution Banner

    private var validationCautionBanner: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(AppColors.warning)
                Text("Things to Keep in Mind")
                    .font(AppFonts.bodySemiBold)
                    .foregroundColor(AppColors.primaryText)
            }
            ForEach(Array(cautionWarnings.enumerated()), id: \.offset) { _, warning in
                Text("• \(warning.message)")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding()
        .background(AppColors.warning.opacity(0.08))
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Summary

    private var overallSummaryCard: some View {
        ExpandableSummaryView(
            fullText: analysisResult.overallSummary,
            presentation: .card(icon: "heart.text.clipboard", iconColor: AppColors.accent, title: "What We Found"),
            detailTitle: "What We Found",
            detailAnalyticsName: "FullText.AnalysisResult",
            accessibilityPrefix: "analysisResult"
        )
    }

    // MARK: - Verification Trust Badge

    /// Surfaces the (otherwise invisible) two-call devil's-advocate verification +
    /// safety-validation pipeline so results don't look like one quick AI guess (audit #27).
    private var verificationBadge: some View {
        Button(action: { showVerificationInfo = true }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(AppColors.success)
                Text("Reviewed by a second AI pass + safety checks")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity)
            .background(AppColors.success.opacity(0.08))
            .cornerRadius(AppCorners.card)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("analysisResult.verificationBadge")
    }

    /// Whether any red flag (app- or AI-detected) is present — gates the plan CTA.
    private var hasAnyRedFlag: Bool {
        !redFlagAlerts.isEmpty || analysisResult.conditions.contains(where: { $0.isRedFlag })
    }

    /// Conditions to render as cards.
    ///
    /// The validation pipeline already bounds this array (ConditionRetentionPolicy),
    /// so the view's former `.prefix(3)` only served to hide a preserved red flag —
    /// and the card is what carries `nextSteps`/`howToManage`, while the banner
    /// carries only `redFlagMessage`. A frightening sentence with no next steps is
    /// worse than none. Red flags render first so a serious finding isn't buried
    /// below three benign cards; the model array order is left untouched so the
    /// Progress tab's `conditions.first` still shows the likeliest cause.
    private var displayedConditions: [ConditionResult] {
        analysisResult.conditions.filter(\.isRedFlag)
            + analysisResult.conditions.filter { !$0.isRedFlag }
    }

    /// Red-flag messages shown in the acknowledgement sheet, de-duplicated against
    /// the app-detected alerts so the same sentence isn't printed twice.
    private var aiRedFlagMessages: [String] {
        let existing = Set(redFlagAlerts.map(\.message))
        return analysisResult.conditions
            .filter(\.isRedFlag)
            .compactMap(\.redFlagMessage)
            .filter { !$0.isEmpty && !existing.contains($0) }
    }

    // MARK: - Condition Card

    private func conditionCard(for condition: ConditionResult) -> some View {
        let strength = ConfidenceCalibrator.matchStrength(for: condition.confidence)
        let isExpanded = expandedConditions.contains(condition.id.uuidString)

        return HStack(spacing: 0) {
            // Colored accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(matchColor(strength))
                .frame(width: 4)
                .padding(.vertical, AppSpacing.sm)

            VStack(alignment: .leading, spacing: 0) {
                // Header — always visible
                Button(action: {
                    withAnimation(AppAnimations.springy) {
                        if isExpanded {
                            expandedConditions.remove(condition.id.uuidString)
                        } else {
                            expandedConditions.insert(condition.id.uuidString)
                        }
                    }
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: AppSpacing.nano) {
                                Text(condition.commonName)
                                    .font(AppFonts.sectionTitle)
                                    .foregroundColor(AppColors.primaryText)
                                // Label the clinical term so it reads as context,
                                // not a scary standalone diagnosis (audit #30).
                                Text("Medical term: \(condition.conditionName)")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                        }

                        // Match strength indicator
                        HStack(spacing: AppSpacing.sm) {
                            matchStrengthDots(strength)
                            Text(strength.rawValue)
                                .font(AppFonts.captionMedium)
                                .foregroundColor(matchColor(strength))

                            Button(action: { showConfidenceInfo = true }) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Match strength information")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(condition.commonName), \(strength.rawValue)")
                        .accessibilityAction(named: "Match strength information") { showConfidenceInfo = true }

                        // Red flag inline warning
                        if condition.isRedFlag {
                            HStack(spacing: AppSpacing.tight) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                Text(condition.redFlagMessage ?? "Seek immediate medical attention")
                                    .font(AppFonts.captionMedium)
                            }
                            .foregroundColor(AppColors.ctaText)
                            .padding(AppSpacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.danger)
                            .cornerRadius(AppCorners.small)
                        }
                    }
                    .padding(AppSpacing.lg)
                }
                .buttonStyle(.plain)

                // Expandable details
                if isExpanded {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        // Thin separator
                        Rectangle()
                            .fill(AppColors.elevatedSurface)
                            .frame(height: 1)
                            .padding(.horizontal, AppSpacing.lg)

                        // Explanation
                        Text(condition.explanation)
                            .font(AppFonts.body)
                            .foregroundColor(AppColors.primaryText)
                            .lineSpacing(3)
                            .padding(.horizontal, AppSpacing.lg)

                        // What's happening
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Label("What's happening", systemImage: "figure.stand")
                                .font(AppFonts.bodySemiBold)
                                .foregroundColor(AppColors.accentText)
                            Text(condition.whatItMeans)
                                .font(AppFonts.body)
                                .foregroundColor(AppColors.secondaryText)
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, AppSpacing.lg)

                        // Next steps
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Label("Suggested next steps", systemImage: "list.number")
                                .font(AppFonts.bodySemiBold)
                                .foregroundColor(AppColors.accentText)
                            ForEach(Array(condition.nextSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: AppSpacing.sm) {
                                    Text("\(index + 1).")
                                        .font(AppFonts.bodySemiBold)
                                        .foregroundColor(AppColors.accentText)
                                        .frame(width: 20, alignment: .leading)
                                    Text(step)
                                        .font(AppFonts.body)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)

                        // How to manage this — the AI already generates this per
                        // condition; surface it here instead of discarding it (audit #29).
                        if !condition.howToManage.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Label("How to manage this", systemImage: "cross.case")
                                    .font(AppFonts.bodySemiBold)
                                    .foregroundColor(AppColors.accentText)
                                Text(condition.howToManage)
                                    .font(AppFonts.body)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineSpacing(3)
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                    .padding(.bottom, AppSpacing.lg)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.xl)
        .shadow(color: AppColors.cardShadowColor, radius: 10, y: 3)
    }

    private func matchStrengthDots(_ strength: MatchStrength) -> some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index, strength: strength))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func dotColor(for index: Int, strength: MatchStrength) -> Color {
        let filledCount: Int
        switch strength {
        case .strong: filledCount = 3
        case .moderate: filledCount = 2
        case .weak: filledCount = 1
        }
        return index < filledCount ? matchColor(strength) : AppColors.elevatedSurface
    }

    private func matchColor(_ strength: MatchStrength) -> Color {
        switch strength {
        case .strong: return AppColors.success
        case .moderate: return AppColors.warning
        case .weak: return AppColors.mutedText
        }
    }

    // MARK: - App-Detected Red Flag Alert

    private var appRedFlagAlert: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.comfortable) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(AppColors.ctaText)
                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text("Important Safety Notice")
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.ctaText)
                    Text("Based on what you reported, please read this carefully")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.ctaText.opacity(0.9))
                }
                Spacer()
            }
            ForEach(Array(redFlagAlerts.enumerated()), id: \.offset) { _, alert in
                Text(alert.message)
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.ctaText.opacity(0.95))
            }
        }
        .padding()
        .background(AppColors.danger)
        .cornerRadius(AppCorners.card)
    }

    // MARK: - AI-Detected Red Flag Alert

    private var aiRedFlagAlert: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.comfortable) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(AppColors.ctaText)
                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text("Please Read This Carefully")
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.ctaText)
                    Text("Some of your symptoms may need urgent attention")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.ctaText.opacity(0.9))
                }
                Spacer()
            }
            // De-duplicated against appRedFlagAlert: AI-flagged conditions now also
            // feed redFlagAlerts, so the same sentence would otherwise appear twice.
            ForEach(aiRedFlagMessages, id: \.self) { message in
                Text(message)
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.ctaText.opacity(0.95))
            }
        }
        .padding()
        .background(AppColors.danger.opacity(0.85))
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Buttons

    private var buildRehabPlanButton: some View {
        VStack(spacing: AppSpacing.sm) {
            // When a red flag is present, don't offer a self-guided plan as the
            // headline action — add a clinician nudge and demote to secondary (audit #24).
            if hasAnyRedFlag {
                Label("We recommend seeing a clinician before starting a self-guided plan.",
                      systemImage: "stethoscope")
                    .font(AppFonts.caption)
                    .foregroundColor(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            planCTAButton
        }
        .padding(.top, AppSpacing.lg)
    }

    @ViewBuilder
    private var planCTAButton: some View {
        if hasAnyRedFlag {
            Button(action: {
                if SeriousWarningAcknowledgements.isAcknowledged(planId: analysisResult.id.uuidString) {
                    showPreferencesSheet = true
                } else {
                    showRiskAcknowledgement = true
                }
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "figure.run")
                    Text("Build Rehab Plan Anyway")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("analysisResult.buildRehabPlanButton")
        } else {
            Button(action: { showPreferencesSheet = true }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "figure.run")
                    Text("Build Rehab Plan")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("analysisResult.buildRehabPlanButton")
        }
    }

    // MARK: - Preferences Sheet

    private var rehabPreferencesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    // Equipment
                    CardSection(icon: "dumbbell.fill", color: AppColors.accent, title: "Available Equipment") {
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(RehabPlanPreferences.Equipment.allCases, id: \.self) { option in
                                ChipButton(
                                    label: option.rawValue,
                                    isSelected: rehabVM.preferences.equipment == option,
                                    action: { rehabVM.preferences.equipment = option }
                                )
                            }
                        }
                    }

                    // Session length
                    CardSection(icon: "clock.fill", color: AppColors.accent, title: "Session Length") {
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(RehabPlanPreferences.SessionLength.allCases, id: \.self) { option in
                                ChipButton(
                                    label: option.rawValue,
                                    isSelected: rehabVM.preferences.sessionLength == option,
                                    action: { rehabVM.preferences.sessionLength = option }
                                )
                            }
                        }
                    }

                    // Difficulty
                    CardSection(icon: "speedometer", color: .orange, title: "Difficulty Level") {
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(RehabPlanPreferences.DifficultyPreference.allCases, id: \.self) { option in
                                ChipButton(
                                    label: option.rawValue,
                                    isSelected: rehabVM.preferences.difficulty == option,
                                    action: { rehabVM.preferences.difficulty = option }
                                )
                            }
                        }
                    }

                    Button(action: {
                        pendingPlanGeneration = true
                        showPreferencesSheet = false
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "sparkles")
                            Text("Generate Plan")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle("Plan Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") {
                        pendingPlanGeneration = true
                        showPreferencesSheet = false
                    }
                }
            }
        }
    }

    private var navigationButtons: some View {
        VStack(spacing: AppSpacing.md) {
            DismissButton {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "chevron.left")
                    Text("Back to Assessment")
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(action: {
                NotificationCenter.default.post(name: .popToRoot, object: nil)
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "house")
                    Text("Home")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
