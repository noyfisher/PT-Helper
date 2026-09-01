import SwiftUI

// MARK: - Wizard Step Views

extension PainDetailView {

    // MARK: Step 0 — Pain Type

    var painTypeStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                questionTitle("What type of pain\nare you feeling?", hint: "Select all that apply")
                painTypeSelection
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Step 1 — Pain Intensity

    var intensityStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                questionTitle("How intense\nis the pain?", hint: "Drag the slider to rate your pain")
                painIntensitySlider
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Step 2 — Duration

    var durationStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                questionTitle("How long have\nyou had this pain?", hint: "Choose one")
                autoAdvanceDurationPicker
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var autoAdvanceDurationPicker: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(painDurationOptions, id: \.self) { duration in
                optionCard(
                    label: duration,
                    isSelected: painDurations.contains(duration),
                    action: {
                        painDurations = [duration]
                        scheduleAutoAdvance()
                    }
                )
            }
        }
    }

    // MARK: Step 3 — Frequency

    var frequencyStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                questionTitle("How often do\nyou feel it?", hint: "Select all that apply")
                painFrequencyPicker
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Step 4 — Onset

    var onsetStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                questionTitle("How did this\npain start?", hint: "Select all that apply")
                painOnsetPicker
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Step 5 — Aggravating Factors

    var aggravatingStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                questionTitle("What makes\nit worse?", hint: "Select all that apply")
                aggravatingFactorsSelection
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Step 6 — Relieving Factors

    var relievingStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                questionTitle("What helps\nrelieve it?", hint: "Select all that apply")
                relievingFactorsSelection
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Step 7 — Summary

    var summaryStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Review Your\nAssessment")
                        .font(AppFonts.heroTitle)
                        .textCase(.uppercase)
                        .kerning(0.3)
                        .foregroundColor(AppColors.primaryText)
                    if let region = viewModel.currentRegion {
                        Text(region.name)
                            .font(AppFonts.small)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                .padding(.top, AppSpacing.sm)
                .accessibilityIdentifier("painDetail.summaryCard")

                CardSection(icon: "bolt.fill", color: AppColors.accent, title: "Pain Type & Intensity") {
                    VStack(spacing: AppSpacing.md) {
                        summaryChipsRow(label: "Type", values: painTypes)
                        summaryRow(
                            label: "Intensity",
                            value: "\(Int(painIntensity)) / 10 — \(painDescription)",
                            valueColor: painColor
                        )
                    }
                }

                CardSection(icon: "clock.fill", color: AppColors.warning, title: "Duration & Frequency") {
                    VStack(spacing: AppSpacing.md) {
                        summaryRow(label: "Duration", value: painDurations.first ?? "—")
                        summaryChipsRow(label: "Frequency", values: painFrequencies)
                    }
                }

                CardSection(icon: "arrow.triangle.2.circlepath", color: AppColors.danger, title: "Onset & Triggers") {
                    VStack(spacing: AppSpacing.md) {
                        summaryChipsRow(label: "Started", values: painOnsets)
                        summaryChipsRow(label: "Worsened by", values: aggravatingFactors)
                        summaryChipsRow(label: "Relieved by", values: relievingFactors)
                    }
                }

                CardSection(icon: "note.text", color: AppColors.secondaryText, title: "Additional Notes") {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Optional — anything else you'd like to add")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.secondaryText)
                        TextField(
                            "",
                            text: $additionalNotes,
                            prompt: Text("e.g., worse in the morning, started after exercise...").foregroundColor(AppColors.mutedText),
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .foregroundColor(AppColors.primaryText)
                        .padding(AppSpacing.md)
                        .background(AppColors.inputBackground)
                        .cornerRadius(AppCorners.medium)
                    }
                }

                if viewModel.hasMultipleRegions {
                    Button(action: { showApplyToAllConfirmation = true }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "doc.on.doc")
                            Text("Apply to All \(viewModel.totalRegions) Regions & Analyze")
                        }
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(AppColors.ctaText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.healingGradient)
                        .cornerRadius(AppCorners.large)
                    }
                    .accessibilityIdentifier("painDetail.applyToAllButton")
                }

                Spacer(minLength: 140)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Option Card

    func optionCard(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: iconForOption(label))
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.secondaryText)
                    .frame(width: 28)
                Text(label)
                    .font(isSelected ? AppFonts.bodySemiBold : AppFonts.body)
                    .foregroundColor(AppColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.elevatedSurface)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md + 2)
            .background(
                RoundedRectangle(cornerRadius: AppCorners.medium)
                    .fill(isSelected ? AppColors.accentTint : AppColors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.medium)
                    .stroke(isSelected ? AppColors.accent : AppColors.cardBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            // .plain buttons only hit-test rendered pixels — keep an explicit
            // content shape so the full row stays tappable (F5 bug class).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Every wizard step builds its choices through this one card, so a single
        // label-derived identifier makes all 8 steps addressable from XCUITest. Without
        // it the wizard carried only two identifiers total and the assessment journey —
        // the app's primary flow — could not be driven end to end at all.
        .accessibilityIdentifier("painDetail.option.\(label)")
        .animation(AppAnimations.springy, value: isSelected)
    }

    // MARK: - Option Icon Lookup

    func iconForOption(_ label: String) -> String {
        switch label {
        // Pain types
        case "Sharp":       return "bolt.fill"
        case "Dull":        return "circle.fill"
        case "Burning":     return "flame.fill"
        case "Throbbing":   return "heart.fill"
        case "Aching":      return "waveform.path.ecg"
        case "Stabbing":    return "arrow.up.right"
        case "Tingling":    return "sparkles"
        case "Tightness":   return "arrow.up.and.down"
        // Duration
        case "Today":               return "sun.max.fill"
        case "A Few Days":          return "calendar"
        case "1-2 Weeks":           return "calendar.badge.clock"
        case "2-4 Weeks":           return "calendar.badge.plus"
        case "Over a Month":        return "calendar.badge.exclamationmark"
        case "Over 3 Months":       return "clock.badge.exclamationmark"
        // Frequency
        case "Constant":            return "repeat"
        case "Intermittent":        return "arrow.triangle.2.circlepath"
        case "Only with Activity":  return "figure.run"
        case "Only at Rest":        return "bed.double.fill"
        case "At Night":            return "moon.fill"
        // Onset
        case "Sudden":          return "bolt.circle.fill"
        case "Gradual":         return "chart.line.uptrend.xyaxis"
        case "After Injury":    return "bandage.fill"
        case "After Surgery":   return "cross.case.fill"
        case "Unknown":         return "questionmark.circle"
        // Movement / aggravating
        case "Walking":                         return "figure.walk"
        case "Running":                         return "figure.run"
        case "Sitting", "Sitting long",
             "Sitting at desk":                 return "person.crop.rectangle"
        case "Lifting", "Lifting overhead":     return "dumbbell.fill"
        case "Twisting":                        return "arrow.clockwise"
        case "Standing long":                   return "figure.stand"
        case "Climbing stairs":                 return "stairs"
        case "Squatting":                       return "figure.strengthtraining.functional"
        case "Jumping":                         return "figure.jumprope"
        case "Pushing", "Push-ups":             return "arrow.right.circle"
        case "Pulling":                         return "arrow.left.circle"
        case "Reaching overhead":               return "arrow.up.circle"
        case "Reaching forward":                return "arrow.forward.circle"
        case "Reaching behind back":            return "arrow.backward.circle"
        case "Gripping":                        return "hand.grip"
        case "Typing", "Writing":               return "keyboard"
        case "Driving":                         return "car.fill"
        case "Turning head":                    return "arrow.counterclockwise.circle"
        case "Looking up":                      return "arrow.up"
        case "Looking down":                    return "arrow.down"
        case "Sleeping position":               return "moon.zzz.fill"
        case "Deep breathing":                  return "lungs.fill"
        case "Coughing", "Coughing/sneezing":   return "waveform"
        case "Bending forward":                 return "arrow.down.forward"
        case "Getting out of bed":              return "sunrise.fill"
        case "Throwing", "Kicking":             return "figure.baseball"
        case "Carrying", "Carrying bags":       return "bag.fill"
        case "Crossing legs":                   return "person.fill"
        case "First steps in morning":          return "sunrise"
        case "Uneven surfaces":                 return "map.fill"
        case "Using phone":                     return "iphone"
        case "Opening jars":                    return "cylinder.fill"
        case "Using tools":                     return "wrench.and.screwdriver.fill"
        case "Bright lights":                   return "sun.max.fill"
        case "Stress/tension":                  return "brain.head.profile"
        case "Lack of sleep":                   return "zzz"
        case "Physical exertion":               return "bolt.heart.fill"
        case "Concentrating":                   return "eye.fill"
        case "Looking at screens":              return "display"
        case "Eating":                          return "fork.knife"
        // Relieving
        case "Rest":                            return "bed.double.fill"
        case "Ice":                             return "snowflake"
        case "Heat":                            return "flame.fill"
        case "Medication":                      return "pills.fill"
        case "Elevation":                       return "arrow.up.circle.fill"
        case "Stretching", "Gentle stretching",
             "Stretching calves", "Stretching forearm": return "figure.flexibility"
        case "Massage":                         return "hand.raised.fill"
        case "Foam rolling":                    return "oval.fill"
        case "Compression", "Compression wrap": return "bandage.fill"
        case "Posture correction":              return "person.fill.checkmark"
        case "Hydration":                       return "drop.fill"
        case "Sleep":                           return "moon.zzz.fill"
        case "Lying down":                      return "bed.double.fill"
        case "Ergonomic adjustments":           return "chair.lounge.fill"
        case "Upright position":                return "arrow.up.circle"
        case "Quiet dark room":                 return "moon.fill"
        case "Reducing screen time":            return "display.trianglebadge.exclamationmark"
        case "Neck support pillow":             return "moon.zzz.fill"
        case "Lumbar support":                  return "rectangle.portrait.fill"
        case "Knee brace", "Wrist brace/splint",
             "Ankle brace", "Arm support/sling",
             "Forearm brace":                   return "bandage.fill"
        case "Gentle walking":                  return "figure.walk"
        case "Gentle movement",
             "Avoiding triggers",
             "Avoiding overhead reach",
             "Avoiding lifting",
             "Avoiding gripping",
             "Avoiding sitting long":           return "hand.raised.slash"
        case "Gentle breathing exercises":      return "lungs.fill"
        case "Cold compress":                   return "snowflake"
        case "Avoiding stairs":                 return "stairs"
        case "Supportive shoes":                return "shoeprints.fill"
        default:                                return "circle"
        }
    }

    // MARK: - Question Title

    func questionTitle(_ text: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(text)
                .font(AppFonts.heroTitle)
                .textCase(.uppercase)
                .kerning(0.3)
                .foregroundColor(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint)
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
    }

    // MARK: - Summary Row Helpers

    func summaryRow(label: String, value: String, valueColor: Color = AppColors.primaryText) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Text(label)
                .font(AppFonts.captionSemiBold)
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 90, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(AppFonts.body)
                .foregroundColor(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func summaryChipsRow(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Text(label)
                .font(AppFonts.captionSemiBold)
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 90, alignment: .leading)
            if values.isEmpty {
                Text("—")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.primaryText)
            } else {
                FlowLayout(spacing: AppSpacing.xs) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(AppFonts.captionMedium)
                            .foregroundColor(AppColors.accentText)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(AppColors.accentTint)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
