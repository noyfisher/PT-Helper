import SwiftUI

struct WellnessResultView: View {
    @ObservedObject var viewModel: WellnessAnalysisViewModel
    @State private var expandedRecommendations: Set<String> = []
    @State private var showPreferencesSheet = false
    @State private var showWellnessPlan = false
    /// Set when the user taps Generate/Skip in the preferences sheet. Generation and the
    /// navigation push are deferred to the sheet's onDismiss — mutating the navigation
    /// destination (or publishing from planVM) in the same transaction as the sheet
    /// dismissal sends SwiftUI into an infinite layout loop that freezes the app.
    @State private var pendingPlanGeneration = false
    @StateObject private var planVM = WellnessPlanViewModel()
    // NOTE: no @Environment(\.dismiss) here — this view registers a
    // navigationDestination, and reading dismiss alongside it causes the
    // infinite-render freeze documented in Components/DismissButton.swift.

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    if viewModel.validationWarnings.contains(where: { $0.severity >= .serious }) {
                        urgentWarningBanner
                    }
                    disclaimerBanner
                    overallSummaryCard

                    if let result = viewModel.analysisResult {
                        ForEach(result.recommendations) { rec in
                            recommendationCard(for: rec)
                        }
                    }

                    buildWellnessPlanButton
                    navigationButtons
                }
                .padding(AppSpacing.xl)
            }
        }
        .navigationTitle("Wellness Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showWellnessPlan) {
            if let result = viewModel.analysisResult {
                WellnessPlanView(viewModel: planVM, wellnessResult: result)
            }
        }
        .sheet(isPresented: $showPreferencesSheet, onDismiss: {
            guard pendingPlanGeneration else { return }
            pendingPlanGeneration = false
            if let result = viewModel.analysisResult {
                planVM.generateWellnessPlan(from: result)
            }
            showWellnessPlan = true
        }) {
            preferencesSheet
        }
        .trackScreen("WellnessResult")
    }

    // MARK: - Urgent Warning Banner

    private var urgentWarningBanner: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.comfortable) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2).foregroundColor(AppColors.ctaText)
                Text("Important Safety Notice")
                    .font(AppFonts.cardTitle).foregroundColor(AppColors.ctaText)
                Spacer()
            }
            ForEach(viewModel.validationWarnings.filter { $0.severity >= .serious }, id: \.message) { w in
                Text(w.message).font(AppFonts.body)
                    .foregroundColor(AppColors.ctaText.opacity(0.95))
            }
        }
        .padding().background(AppColors.danger).cornerRadius(AppCorners.card)
    }

    // MARK: - Disclaimer

    private var disclaimerBanner: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(AppColors.accent)
            Text(viewModel.analysisResult?.disclaimerText ?? "This is educational wellness guidance — not a medical diagnosis or treatment plan.")
                .font(AppFonts.caption)
                // accentTint over the fixed-dark bgGradient — the adaptive token
                // goes dark-on-dark in light mode.
                .foregroundColor(AppColors.textOnDarkMuted)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentTint)
        .cornerRadius(AppCorners.medium)
    }

    // MARK: - Overall Summary

    private var overallSummaryCard: some View {
        ExpandableSummaryView(
            fullText: viewModel.analysisResult?.overallSummary ?? "",
            presentation: .card(icon: "text.alignleft", iconColor: AppColors.accent, title: "Summary"),
            detailTitle: "Summary",
            detailAnalyticsName: "FullText.WellnessResult",
            accessibilityPrefix: "wellnessResult"
        )
    }

    // MARK: - Recommendation Card

    private func recommendationCard(for rec: WellnessRecommendation) -> some View {
        let isExpanded = expandedRecommendations.contains(rec.id.uuidString)
        let priorityColor = priorityColor(for: rec.priorityLevel)

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                // Header (tap to expand)
                Button(action: {
                    withAnimation(AppAnimations.springy) {
                        if isExpanded {
                            expandedRecommendations.remove(rec.id.uuidString)
                        } else {
                            expandedRecommendations.insert(rec.id.uuidString)
                        }
                    }
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            Text(rec.title)
                                .font(AppFonts.sectionTitle)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(AppColors.secondaryText)
                        }

                        HStack(spacing: AppSpacing.sm) {
                            Text(rec.priorityLevel.capitalized)
                                .font(AppFonts.captionMedium)
                                .foregroundColor(priorityColor)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.nano)
                                .background(priorityColor.opacity(0.12))
                                .cornerRadius(AppCorners.small)

                            if let category = GoalCategory(rawValue: rec.goalCategory) {
                                Image(systemName: category.icon)
                                    .font(AppFonts.caption)
                                    .foregroundColor(category.color)
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                }
                .buttonStyle(.plain)

                // Expanded details
                if isExpanded {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 1)
                            .padding(.horizontal, AppSpacing.lg)

                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            // Current state
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Label("Where you are now", systemImage: "location.fill")
                                    .font(AppFonts.bodySemiBold)
                                    .foregroundColor(AppColors.accentText)
                                Text(rec.currentStateAssessment)
                                    .font(AppFonts.body)
                            }

                            // Root causes
                            if !rec.rootCauses.isEmpty {
                                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                    Label("Likely root causes", systemImage: "magnifyingglass")
                                        .font(AppFonts.bodySemiBold)
                                        .foregroundColor(AppColors.warning)
                                    ForEach(rec.rootCauses, id: \.self) { cause in
                                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                                            Text("•")
                                                .font(AppFonts.bodySemiBold)
                                            Text(cause)
                                                .font(AppFonts.body)
                                        }
                                    }
                                }
                            }

                            // Key insight
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(Color(CoilPalette.pop))
                                Text(rec.keyInsight)
                                    .font(AppFonts.bodyMedium)
                            }
                            .padding(AppSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(CoilPalette.pop).opacity(0.1))
                            .cornerRadius(AppCorners.small)

                            // Timeline
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(AppColors.accent)
                                Text(rec.expectedTimeline)
                                    .font(AppFonts.body)
                                    .foregroundColor(AppColors.secondaryText)
                            }

                            // Related goals
                            if !rec.relatedGoals.isEmpty {
                                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                    Text("Related goals")
                                        .font(AppFonts.captionMedium)
                                        .foregroundColor(AppColors.secondaryText)
                                    FlowLayout(spacing: AppSpacing.sm) {
                                        ForEach(rec.relatedGoals, id: \.self) { goal in
                                            Text(goal)
                                                .font(AppFonts.caption)
                                                .padding(.horizontal, AppSpacing.sm)
                                                .padding(.vertical, AppSpacing.xs)
                                                .background(AppColors.accentTint)
                                                .cornerRadius(AppCorners.small)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.lg)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.xl)
        .shadow(color: AppColors.cardShadowColor, radius: 10, y: 3)
    }

    private func priorityColor(for priority: String) -> Color {
        switch priority.lowercased() {
        case "high": return AppColors.danger
        case "medium": return AppColors.warning
        case "low": return AppColors.success
        default: return AppColors.accent
        }
    }

    // MARK: - Build Plan Button

    private var buildWellnessPlanButton: some View {
        Button(action: { showPreferencesSheet = true }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "figure.flexibility")
                Text("Build My Wellness Plan")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, AppSpacing.lg)
        .accessibilityIdentifier("wellnessResult.buildPlanButton")
    }

    // MARK: - Preferences Sheet

    private var preferencesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    CardSection(icon: "dumbbell.fill", color: AppColors.accent, title: "Available Equipment") {
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(RehabPlanPreferences.Equipment.allCases, id: \.self) { option in
                                ChipButton(
                                    label: option.rawValue,
                                    isSelected: planVM.preferences.equipment == option,
                                    action: { planVM.preferences.equipment = option }
                                )
                            }
                        }
                    }

                    CardSection(icon: "clock.fill", color: AppColors.accent, title: "Session Length") {
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(RehabPlanPreferences.SessionLength.allCases, id: \.self) { option in
                                ChipButton(
                                    label: option.rawValue,
                                    isSelected: planVM.preferences.sessionLength == option,
                                    action: { planVM.preferences.sessionLength = option }
                                )
                            }
                        }
                    }

                    CardSection(icon: "speedometer", color: AppColors.warning, title: "Difficulty Level") {
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(RehabPlanPreferences.DifficultyPreference.allCases, id: \.self) { option in
                                ChipButton(
                                    label: option.rawValue,
                                    isSelected: planVM.preferences.difficulty == option,
                                    action: { planVM.preferences.difficulty = option }
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

    // MARK: - Navigation

    private var navigationButtons: some View {
        VStack(spacing: AppSpacing.md) {
            DismissButton {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "chevron.left")
                    Text("Back to Assessment")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.bottom, AppSpacing.xxl)
    }
}
