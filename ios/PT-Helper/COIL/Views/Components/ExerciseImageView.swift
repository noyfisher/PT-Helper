import SwiftUI

/// Displays AI-generated exercise images when available.
/// Supports: single image, on-demand generation with loading state, and SF Symbol fallback.
struct ExerciseImageView: View {
    let exercise: RehabExercise
    var isCompact: Bool = false

    @State private var startImage: UIImage?
    @State private var endImage: UIImage?
    @State private var showingEnd = false
    @State private var isGenerating = false
    @State private var generationFailed = false

    private var imageSize: CGFloat { isCompact ? 50 : 280 }
    private var cornerRadius: CGFloat { isCompact ? 10 : 16 }

    /// Cross-fade timing: hold each pose for this long, then fade for ~0.4s.
    private let holdSeconds: Double = 1.5

    var body: some View {
        Group {
            if let start = startImage {
                imageContent(start)
            } else if isGenerating {
                generatingContent
            } else {
                fallbackContent
            }
        }
        .task(id: exercise.id) {
            // Reset state on exercise change so a recycled view doesn't show the prior image.
            startImage = nil
            endImage = nil
            showingEnd = false
            generationFailed = false

            await ExerciseImageService.shared.fetchRemoteAliases()

            startImage = await ExerciseImageService.shared.loadImage(for: exercise)

            if startImage == nil, !isCompact {
                isGenerating = true
                let generated = await ExerciseImageService.shared.requestImageGeneration(for: exercise)
                if let generated {
                    startImage = generated
                } else {
                    generationFailed = true
                }
                isGenerating = false
            }

            if !isCompact, startImage != nil {
                endImage = await ExerciseImageService.shared.loadEndImage(for: exercise)
            }

            ExerciseImageService.shared.logMissingImageIfNeeded(for: exercise)

            // Run the cross-fade INSIDE this structured task rather than spawning a
            // detached one. The old `Task { while … }` outlived the view: it was
            // never cancelled on teardown, ignored cancellation (`try?` swallowed
            // it), and its captured @State boxes kept the loop alive with nothing
            // left to render into — one leaked ticker per exercise card shown.
            if endImage != nil {
                await runCrossFadeLoop()
            }
        }
    }

    /// Cross-fade between the start and end frames until the enclosing `.task`
    /// is cancelled — i.e. until the view goes away. `Task.sleep` throws on
    /// cancellation and that is deliberately allowed to end the loop.
    private func runCrossFadeLoop() async {
        while endImage != nil && startImage != nil {
            do {
                try await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
            } catch {
                return  // cancelled — the view is gone
            }
            guard !Task.isCancelled, endImage != nil else { return }
            withAnimation(.easeInOut(duration: 0.4)) { showingEnd.toggle() }
        }
    }

    // MARK: - Single Image Content

    @ViewBuilder
    private func imageContent(_ image: UIImage) -> some View {
        if isCompact {
            compactImageView(image)
        } else {
            fullImageView(image)
        }
    }

    private func compactImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(difficultyColor.opacity(0.3), lineWidth: 1.5)
            )
            // Decorative thumbnail — the exercise name is announced right next to
            // it in list rows, so don't double-announce a bare image (audit #67).
            .accessibilityHidden(true)
    }

    private func fullImageView(_ image: UIImage) -> some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: imageSize, maxHeight: imageSize)
                    .opacity(showingEnd && endImage != nil ? 0 : 1)

                if let end = endImage {
                    Image(uiImage: end)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: imageSize, maxHeight: imageSize)
                        .opacity(showingEnd ? 1 : 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(difficultyColor.opacity(0.15), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            // Announce the pose so VoiceOver users can follow the movement in an
            // app where doing an exercise wrong risks re-injury (audit #67).
            .accessibilityElement()
            .accessibilityLabel(showingEnd && endImage != nil
                                 ? "End position for \(exercise.name)"
                                 : "Start position for \(exercise.name)")

            // Difficulty badge
            DifficultyBadge(difficulty: exercise.difficulty)
        }
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: - Generating State

    private var generatingContent: some View {
        VStack(spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColors.cardBackground)
                .frame(width: imageSize, height: imageSize)
                .overlay(
                    VStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Creating illustration...")
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                )
                .modifier(ShimmerModifier())

            DifficultyBadge(difficulty: exercise.difficulty)
        }
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: - Fallback (SF Symbol)

    private var fallbackContent: some View {
        ExerciseIllustrationView(
            iconName: ExerciseIconMapper.icon(for: exercise),
            difficulty: exercise.difficulty,
            isCompact: isCompact
        )
    }

    // MARK: - Helpers

    private var difficultyColor: Color {
        switch exercise.difficulty {
        case .beginner: return .green
        case .intermediate: return AppColors.accent
        case .advanced: return AppColors.accent
        }
    }
}

// ShimmerModifier is defined in DesignSystem.swift
