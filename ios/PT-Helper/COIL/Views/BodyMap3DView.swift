import SwiftUI
import RealityKit
import Combine

/// 3D interactive body map using RealityKit.
/// Users can tap body regions to select/deselect them,
/// drag horizontally to rotate, drag vertically to scroll when zoomed,
/// and pinch to zoom.
struct BodyMap3DView: View {
    @StateObject private var viewModel = BodyMapViewModel()

    // MARK: - Navigation State

    @State private var navigateToPainDetail = false
    /// Bumped by Retry to give the RealityView a new identity, which is the only
    /// way to re-run its make closure.
    @State private var modelReloadToken = 0
    @State private var showRegionList = false
    @State private var showDisclaimer = false
    /// MHMDA health-data consent gate (shown before the disclaimer on first use).
    @State private var showHealthConsent = false
    /// Stable ViewModel for injury analysis — created before navigation flag is set,
    /// cleaned up via onChange when navigation pops back.
    @State private var injuryAnalysisVM: InjuryAnalysisViewModel?

    // MARK: - Model State

    @State private var pivotEntity: Entity?
    @State private var bodyEntity: Entity?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var originalMaterials: [String: [any RealityKit.Material]] = [:]

    // MARK: - Transform State

    @State private var accumulatedRotation: Float = 0
    @State private var accumulatedPanY: Float = 0
    @State private var accumulatedScale: Float = 1.0

    // MARK: - Gesture State

    @State private var isPinching: Bool = false
    @State private var previousDragTranslation: CGSize = .zero

    // MARK: - Momentum State

    @State private var rotationVelocity: Float = 0
    @State private var momentumTimer: AnyCancellable?
    @State private var lastDragTime: Date?
    @State private var lastDragTranslationX: CGFloat = 0

    // MARK: - Zone Drill-Down State

    @State private var activeZone: BodyZone?
    /// Set of zoneKeys for entities hidden during drill-down.
    @State private var hiddenEntityKeys: Set<String> = []

    // MARK: - UI State

    @State private var lastTappedName: String?
    @State private var showCoachMark = false
    @AppStorage(AppStorageKeys.hasSeenBodyMapCoach) private var hasSeenCoach = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(uiColor: BodyMapConstants.sceneBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                selectedRegionsPills

                ZStack {
                    model3DSection

                    if isLoading {
                        loadingOverlay
                    }

                    if let error = loadError {
                        modelErrorView(error)
                    }

                    if let name = lastTappedName {
                        regionNameToast(name)
                    }

                    // First-time coach mark overlay
                    if showCoachMark {
                        coachMarkOverlay
                    }
                }

                // Zone sub-region panel (below 3D viewport, visible during drill-down)
                if let zone = activeZone {
                    zoneRegionStrip(zone: zone)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomActions
            }
        }
        .onAppear {
            AnalyticsService.shared.log(.bodyMapOpened)
            if !hasSeenCoach && !isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation { showCoachMark = true }
                }
            }
        }
        .onChange(of: isLoading) { _, newValue in
            if !newValue && !hasSeenCoach {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { showCoachMark = true }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .coilNavBar()
        .sheet(isPresented: $showHealthConsent, onDismiss: {
            // Chain into the disclaimer once consent is granted (never in the same
            // transaction as the dismissal — Gotcha #2). When the disclaimer was
            // already accepted, continue straight to the pain form — previously
            // this branch did nothing and the user's Continue tap dead-ended back
            // on the body map. Mirrors WellnessGoalPickerView's chain.
            if ConsentService.shared.hasHealthDataConsent && !DisclaimerManager.hasAccepted {
                showDisclaimer = true
            } else if ConsentService.shared.hasHealthDataConsent {
                injuryAnalysisVM = InjuryAnalysisViewModel(
                    userProfile: viewModel.userProfile,
                    selectedRegions: viewModel.selectedRegions
                )
                navigateToPainDetail = true
            }
        }) {
            HealthDataConsentView(
                onConsented: { showHealthConsent = false },
                onNotNow: { showHealthConsent = false })
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView(onAccept: {
                injuryAnalysisVM = InjuryAnalysisViewModel(
                    userProfile: viewModel.userProfile,
                    selectedRegions: viewModel.selectedRegions
                )
                navigateToPainDetail = true
            })
        }
        .sheet(isPresented: $showRegionList) {
            regionListSheet
        }
        .onChange(of: navigateToPainDetail) { _, navigating in
            if !navigating {
                injuryAnalysisVM = nil
            }
        }
        .navigationDestination(isPresented: $navigateToPainDetail) {
            if let vm = injuryAnalysisVM {
                PainDetailView(viewModel: vm)
            }
        }
        .trackScreen("BodyMap3D")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            if let zone = activeZone {
                // Drill-down header with back button and zone name
                HStack {
                    Button(action: exitDrillDown) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .bold))
                            Text("Back")
                                .font(AppFonts.smallMedium)
                        }
                        .foregroundColor(AppColors.primaryText.opacity(0.8))
                    }

                    Spacer()

                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: zone.iconName)
                            .font(.system(size: 16))
                        Text(zone.displayName)
                            .font(AppFonts.sectionTitle)
                    }
                    .foregroundColor(AppColors.primaryText)

                    Spacer()

                    // Invisible spacer to balance the back button
                    Color.clear.frame(width: 60, height: 1)
                }
                Text("Tap regions to select specific areas")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.mutedText)
            } else {
                // Overview header
                Text("Where does it hurt?")
                    .font(AppFonts.sectionTitle)
                    .foregroundColor(AppColors.primaryText)
                Text("Tap a body zone to zoom in")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.mutedText)
                    .multilineTextAlignment(.center)
                // Always-visible rotate cue (not just the one-time coach mark) so
                // returning users know the model turns — that's where the back,
                // glutes & hamstrings live (audit #18).
                Label("Drag to rotate — reach the back, glutes & hamstrings", systemImage: "arrow.triangle.2.circlepath")
                    .font(AppFonts.micro)
                    .foregroundColor(AppColors.accentText)
                    .multilineTextAlignment(.center)

                // Non-visual path: a VoiceOver user can't tap the 3D RealityKit
                // model, so give them a list to select regions from — otherwise the
                // whole assessment funnel dead-ends at step one (audit #64).
                Button {
                    showRegionList = true
                } label: {
                    Label("Choose from a list", systemImage: "list.bullet")
                        .font(AppFonts.captionMedium)
                }
                .padding(.top, AppSpacing.xs)
                .accessibilityIdentifier("bodyMap.chooseFromListButton")
            }
        }
        .padding(.top, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.xl)
        .animation(.easeInOut(duration: 0.25), value: activeZone)
    }

    // MARK: - Accessible Region List (audit #64)

    /// VoiceOver-reachable list of body regions (grouped by zone) that toggles the
    /// same selection the 3D model does — driven by the same `BodyZone` data.
    private var regionListSheet: some View {
        NavigationStack {
            List {
                ForEach(BodyZone.allCases) { zone in
                    let zoneRegions = viewModel.regions.filter { zone.regionZoneKeys.contains($0.zoneKey) }
                    if !zoneRegions.isEmpty {
                        Section(zone.displayName) {
                            ForEach(zoneRegions, id: \.zoneKey) { region in
                                let isSelected = viewModel.selectedRegions.contains { $0.zoneKey == region.zoneKey }
                                Button {
                                    selectRegion(named: region.zoneKey)
                                } label: {
                                    HStack {
                                        Text(region.name)
                                            .foregroundColor(AppColors.primaryText)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(AppColors.accent)
                                        }
                                    }
                                }
                                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Areas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showRegionList = false }
                }
            }
        }
    }

    // MARK: - Selected Regions Pills

    private var selectedRegionsPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                if viewModel.selectedRegions.isEmpty {
                    Text("No areas selected")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.mutedText)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.elevatedSurface.opacity(0.3))
                        .clipShape(Capsule())
                } else {
                    ForEach(viewModel.selectedRegions, id: \.id) { region in
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(Color(uiColor: BodyMapConstants.highlightColor))
                                .frame(width: 8, height: 8)
                            Text(region.name)
                                .font(AppFonts.captionMedium)
                                .foregroundColor(.white)
                            Button(action: {
                                withAnimation(AppAnimations.springy) {
                                    viewModel.toggleSelection(for: region)
                                }
                                restoreMaterial(for: region.zoneKey)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.white.opacity(0.85))
                            }
                            .accessibilityLabel("Deselect \(region.name)")
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color(uiColor: BodyMapConstants.highlightColor).opacity(0.8))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .frame(height: 40)
        .padding(.top, AppSpacing.sm)
    }

    // MARK: - 3D Model

    private var model3DSection: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual
                // KNOWN GAP (cosmetic, light mode only): the RealityView renders its
                // own opaque backdrop, which reads as a mid-grey slab (~#AFB3B3)
                // against the light page (#F3F5F4). In dark mode the two happen to
                // match, so the viewport only looks seamless there.
                //
                // `content.environment.background` is visionOS-only — it does not
                // exist on iOS — so the scene backdrop cannot simply be painted from
                // `BodyMapConstants.sceneBackground` the way the surrounding SwiftUI
                // layer is. The remaining option is a background plane entity behind
                // the model, which is deliberately NOT done here: this is the app's
                // primary assessment surface and its hit-testing (including the
                // invisible zone proxies) is the fragile part, so trading a colour
                // mismatch for a hit-testing regression is the wrong bargain.

                do {
                    let regionKeys = Set(viewModel.regions.map(\.zoneKey))

                    let entity = try await ConfiguredBodyModelCache.shared.configuredModel(regionKeys: regionKeys) { tpl in
                        configureTemplateGeometry(for: tpl, regionKeys: regionKeys)
                        createProxyEntities(for: tpl, regionKeys: regionKeys)
                        createArmZoneProxies(for: tpl, regionKeys: regionKeys)
                        createLegZoneProxies(for: tpl, regionKeys: regionKeys)
                    }
                    captureOriginalMaterials(from: entity, regionKeys: regionKeys)

                    entity.scale = SIMD3<Float>(repeating: BodyMapConstants.modelScale)

                    let pivot = Entity()
                    entity.position.y = -BodyMapConstants.modelHalfHeight
                    pivot.addChild(entity)

                    content.add(pivot)
                    pivotEntity = pivot
                    bodyEntity = entity
                    isLoading = false

                } catch {
                    AppLogger.data.error("Failed to load body model: \(error.localizedDescription)")
                    isLoading = false
                    loadError = error
                }
            }
            .gesture(doubleTapGesture)
            .gesture(tapGesture)
            .gesture(rotateAndPanGesture)
            .simultaneousGesture(zoomGesture)
            // Present the 3D viewport as ONE accessibility element, not a container.
            //
            // For VoiceOver users the mesh is not operable — region selection by
            // touch needs the hit-testing this view does on taps — so the accessible
            // path is the "Choose from a list" button below, and the label says so
            // rather than exposing an undrivable subtree. No UI test targets anything
            // inside the viewport either; they all use the list fallback.
            //
            // NOT a fix for the XCUITest harness crashes, despite being tried as one.
            // The hypothesis was that the recurring SIGSEGVs in Apple's accessibility
            // snapshot walker came from recursing this view's subtree. Measured over
            // three FullPlan runs after this change: the identical walker crash still
            // occurred (zero COIL frames), so whatever it chokes on is not here. Kept
            // on accessibility merits only.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("3D body map")
            .accessibilityHint("Use Choose from a list to select a region.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // New identity on retry → RealityView rebuilds and its make closure
            // runs again. Without this the Retry button was inert.
            .id(modelReloadToken)

            // Reset button (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    resetViewButton
                        .padding(.trailing, AppSpacing.xl)
                        .padding(.bottom, AppSpacing.md)
                }
            }

        }
    }

    // MARK: - Loading & Error Overlays

    private var loadingOverlay: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppColors.mutedText)
            Text("Loading 3D Model...")
                .font(AppFonts.small)
                .foregroundColor(AppColors.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: BodyMapConstants.loadingOverlayBackground))
    }

    private func modelErrorView(_ error: Error) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text("Unable to Load 3D Model")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Text("Please try again or restart the app.")
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.mutedText)
                    .multilineTextAlignment(.center)
            }

            Button(action: retryModelLoad) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.body.weight(.semibold))
                .foregroundColor(AppColors.ctaText)
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.accent)
                .cornerRadius(AppCorners.card)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: BodyMapConstants.sceneBackground))
    }

    // MARK: - Coach Mark Overlay

    private var coachMarkOverlay: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            VStack(spacing: AppSpacing.xl) {
                HStack(spacing: AppSpacing.xxl) {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AppColors.primaryText)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Tap to zoom in")
                            .font(AppFonts.captionSemiBold)
                            .foregroundColor(AppColors.primaryText)
                    }

                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AppColors.primaryText)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Drag to rotate")
                            .font(AppFonts.captionSemiBold)
                            .foregroundColor(AppColors.primaryText)
                    }

                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 28))
                            .foregroundColor(AppColors.primaryText)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Pinch to zoom")
                            .font(AppFonts.captionSemiBold)
                            .foregroundColor(AppColors.primaryText)
                    }
                }

                Text("Tap a body zone, then select specific areas")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.primaryText.opacity(0.8))

                Button(action: {
                    withAnimation { showCoachMark = false }
                    hasSeenCoach = true
                }) {
                    Text("Got it")
                        .font(AppFonts.smallSemiBold)
                        .foregroundColor(AppColors.accentText)
                        .padding(.horizontal, AppSpacing.xxl)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.pill)
                }
            }
            .padding(AppSpacing.xl)
            .background(AppColors.elevatedSurface)
            .cornerRadius(AppCorners.xl)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.primaryText.opacity(0.3))
        .transition(.opacity)
        .onTapGesture {
            withAnimation { showCoachMark = false }
            hasSeenCoach = true
        }
    }

    private func regionNameToast(_ name: String) -> some View {
        VStack {
            Text(name)
                .font(AppFonts.captionSemiBold)
                .foregroundColor(AppColors.ctaText)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.primaryText.opacity(0.75))
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale))
            Spacer()
        }
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Gestures

    /// Double-tap: exit drill-down if active, otherwise toggle zoom
    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .targetedToAnyEntity()
            .onEnded { _ in
                // If in drill-down, double-tap exits back to overview
                if activeZone != nil {
                    exitDrillDown()
                    return
                }

                guard let pivot = pivotEntity else { return }

                cancelMomentum()

                let targetScale: Float
                if accumulatedScale > 1.5 {
                    targetScale = 1.0
                    accumulatedPanY = 0
                } else {
                    targetScale = BodyMapConstants.doubleTapZoomLevel
                }
                accumulatedScale = targetScale

                var target = pivot.transform
                target.scale = SIMD3<Float>(repeating: targetScale)
                if targetScale <= 1.0 {
                    target.translation.y = 0
                }
                pivot.move(to: target, relativeTo: pivot.parent,
                           duration: 0.35, timingFunction: .easeInOut)

                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
    }

    /// Tap to select/deselect body parts
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                handleEntityTap(value.entity)
            }
    }

    /// Single-finger drag: omni-directional rotation + pan simultaneously
    private var rotateAndPanGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isPinching else { return }
                guard let pivot = pivotEntity else { return }

                // Delta since last frame (for velocity tracking)
                let deltaX = value.translation.width - previousDragTranslation.width
                previousDragTranslation = value.translation

                // Cancel momentum on first move
                if lastDragTime == nil {
                    cancelMomentum()
                    rotationVelocity = 0
                }

                // Rotation from horizontal component (always active)
                let dragAngle = Float(value.translation.width) * BodyMapConstants.rotationSensitivity
                pivot.transform.rotation = simd_quatf(
                    angle: accumulatedRotation + dragAngle,
                    axis: SIMD3<Float>(0, 1, 0)
                )

                // Track velocity for momentum
                let now = Date()
                if let last = lastDragTime {
                    let dt = now.timeIntervalSince(last)
                    if dt > 0.001 {
                        let dx = Float(deltaX) * BodyMapConstants.rotationSensitivity
                        rotationVelocity = dx / Float(dt) / 60.0
                    }
                }
                lastDragTime = now
                lastDragTranslationX = value.translation.width

                // Pan from vertical component (only when zoomed)
                if accumulatedScale > 1.0 {
                    let rawPanY = accumulatedPanY - Float(value.translation.height) * BodyMapConstants.panSensitivity
                    let zoomFactor = max(accumulatedScale - 1.0, 0)
                    let maxPan: Float = zoomFactor * 1.0

                    let clampedPanY: Float
                    if rawPanY > maxPan {
                        clampedPanY = maxPan + (rawPanY - maxPan) * BodyMapConstants.rubberBandFactor
                    } else if rawPanY < -maxPan {
                        clampedPanY = -maxPan - (-maxPan - rawPanY) * BodyMapConstants.rubberBandFactor
                    } else {
                        clampedPanY = rawPanY
                    }
                    pivot.position.y = clampedPanY
                }
            }
            .onEnded { value in
                guard !isPinching else { return }

                // Commit rotation
                accumulatedRotation += Float(value.translation.width) * BodyMapConstants.rotationSensitivity

                // Start momentum if velocity is significant
                if abs(rotationVelocity) > BodyMapConstants.momentumStopThreshold {
                    startRotationMomentum()
                }

                // Commit pan (clamp to bounds, spring back if overshot)
                if accumulatedScale > 1.0 {
                    let rawPanY = accumulatedPanY - Float(value.translation.height) * BodyMapConstants.panSensitivity
                    let zoomFactor = max(accumulatedScale - 1.0, 0)
                    let maxPan: Float = zoomFactor * 1.0
                    accumulatedPanY = min(max(rawPanY, -maxPan), maxPan)

                    if let pivot = pivotEntity,
                       pivot.position.y > maxPan + 0.001 || pivot.position.y < -maxPan - 0.001 {
                        var target = pivot.transform
                        target.translation.y = accumulatedPanY
                        pivot.move(to: target, relativeTo: pivot.parent,
                                   duration: 0.25, timingFunction: .easeInOut)
                    }
                }

                resetGestureTracking()
            }
    }

    /// Pinch to zoom in/out (Phases 1, 6)
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isPinching = true
                guard let pivot = pivotEntity else { return }

                let newScale = accumulatedScale * Float(value.magnification)

                // Phase 6: rubber-band at limits
                let clamped: Float
                if newScale < BodyMapConstants.minScale {
                    clamped = BodyMapConstants.minScale - (BodyMapConstants.minScale - newScale) * BodyMapConstants.rubberBandFactor
                } else if newScale > BodyMapConstants.maxScale {
                    clamped = BodyMapConstants.maxScale + (newScale - BodyMapConstants.maxScale) * BodyMapConstants.rubberBandFactor
                } else {
                    clamped = newScale
                }

                pivot.scale = SIMD3<Float>(repeating: max(clamped, BodyMapConstants.absoluteMinScale))
            }
            .onEnded { value in
                let newScale = accumulatedScale * Float(value.magnification)
                accumulatedScale = min(max(newScale, BodyMapConstants.minScale), BodyMapConstants.maxScale)

                // Clamp existing pan to new zoom's range
                let zoomFactor = max(accumulatedScale - 1.0, 0)
                let maxPan: Float = zoomFactor * 1.0
                accumulatedPanY = min(max(accumulatedPanY, -maxPan), maxPan)

                // If zoomed out to ~1x, snap pan back to center
                if accumulatedScale < BodyMapConstants.snapToCenterThreshold {
                    accumulatedPanY = 0
                }

                // Phase 6: spring back if visually overshot limits
                if let pivot = pivotEntity {
                    let visualScale = pivot.scale.x
                    if visualScale < BodyMapConstants.minScale || visualScale > BodyMapConstants.maxScale
                        || accumulatedScale < BodyMapConstants.snapToCenterThreshold {
                        var target = pivot.transform
                        target.scale = SIMD3<Float>(repeating: accumulatedScale)
                        target.translation.y = accumulatedPanY
                        pivot.move(to: target, relativeTo: pivot.parent,
                                   duration: 0.3, timingFunction: .easeInOut)
                    }
                }

                isPinching = false
            }
    }

    // MARK: - Rotation Momentum (Phase 3)

    private func startRotationMomentum() {
        momentumTimer?.cancel()

        momentumTimer = Timer.publish(every: BodyMapConstants.momentumFPS, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard let pivot = pivotEntity else {
                    cancelMomentum()
                    return
                }

                rotationVelocity *= BodyMapConstants.momentumFriction

                if abs(rotationVelocity) < BodyMapConstants.momentumStopThreshold {
                    cancelMomentum()
                    rotationVelocity = 0
                    return
                }

                accumulatedRotation += rotationVelocity
                pivot.transform.rotation = simd_quatf(
                    angle: accumulatedRotation,
                    axis: SIMD3<Float>(0, 1, 0)
                )
            }
    }

    private func cancelMomentum() {
        momentumTimer?.cancel()
        momentumTimer = nil
    }

    private func resetGestureTracking() {
        previousDragTranslation = .zero
        lastDragTime = nil
        lastDragTranslationX = 0
    }

    // MARK: - Reset View Button

    private var resetViewButton: some View {
        Button(action: resetView) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                Text("Reset")
                    .font(AppFonts.captionSemiBold)
            }
            .foregroundColor(AppColors.primaryText)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.elevatedSurface)
            .clipShape(Capsule())
        }
        .accessibilityIdentifier("bodyMap3D.resetButton")
    }

    // MARK: - Bottom Actions

    /// Self-explaining status line: a nudge when nothing's picked, otherwise a
    /// correctly-pluralized count (audit #21 — fixes "0 area(s) selected").
    private var selectionSummary: String {
        let n = viewModel.selectedRegions.count
        switch n {
        case 0: return "No areas selected yet"
        case 1: return "1 area selected"
        default: return "\(n) areas selected"
        }
    }

    private var bottomActions: some View {
        VStack(spacing: AppSpacing.md) {
            HStack {
                Text(selectionSummary)
                    .font(AppFonts.smallMedium)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                if !viewModel.selectedRegions.isEmpty {
                    Button(action: { clearAllSelections() }) {
                        Text("Clear All")
                            .font(AppFonts.smallMedium)
                            .foregroundColor(AppColors.danger)
                    }
                    .accessibilityIdentifier("bodyMap3D.clearAllButton")
                }
            }

            Button(action: {
                if !ConsentService.shared.hasHealthDataConsent {
                    showHealthConsent = true
                } else if DisclaimerManager.hasAccepted {
                    injuryAnalysisVM = InjuryAnalysisViewModel(
                        userProfile: viewModel.userProfile,
                        selectedRegions: viewModel.selectedRegions
                    )
                    navigateToPainDetail = true
                } else {
                    showDisclaimer = true
                }
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Text(viewModel.selectedRegions.isEmpty ? "Select where it hurts" : "Continue")
                    if !viewModel.selectedRegions.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(
                    viewModel.selectedRegions.isEmpty
                        ? AppColors.mutedText.opacity(0.3)
                        : AppColors.accent
                )
                .foregroundColor(viewModel.selectedRegions.isEmpty ? AppColors.mutedText : AppColors.ctaText)
                .font(.headline)
                .cornerRadius(AppCorners.large)
            }
            .disabled(viewModel.selectedRegions.isEmpty)
            .accessibilityIdentifier("bodyMap3D.continueButton")
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xxl)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Model Setup Helpers

    /// Configure each body-region child for tap interaction and apply region colors.
    /// Pure function of the (fixed) model geometry and the (static) region-key set —
    /// safe to run once on a shared template and reuse across every clone.
    @MainActor
    private func configureTemplateGeometry(for parent: Entity, regionKeys: Set<String>) {
        let zoneBoxedRegions = Set(BodyMapConstants.armRegionOrder
            + BodyMapConstants.lowerLegRegionOrder)
        for child in parent.children {
            if regionKeys.contains(child.name),
               child.components[ModelComponent.self] != nil {
                child.components.set(InputTargetComponent(allowedInputTypes: .indirect))

                let baseKey = BodyMapConstants.regionBaseKey(child.name)
                if zoneBoxedRegions.contains(baseKey) {
                    // Arm regions (createArmZoneProxies) and lower-leg regions
                    // (createLegZoneProxies) use Y-banded zone box proxies.
                    // Their auto-generated convex hulls overlap neighbors
                    // (calf_shin bleeds down past the ankle, etc.), so we skip
                    // them here and let the boxes own the taps.
                } else {
                    child.generateCollisionShapes(recursive: true)
                }

                applyRegionColor(to: child)
            }
            configureTemplateGeometry(for: child, regionKeys: regionKeys)
        }
    }

    /// Capture each region's post-configuration materials into per-view state
    /// (`originalMaterials`) so selection restore has a baseline to revert to.
    /// Read-only — must run per-open, since `originalMaterials` is view-instance state.
    @MainActor
    private func captureOriginalMaterials(from parent: Entity, regionKeys: Set<String>) {
        for child in parent.children {
            if regionKeys.contains(child.name),
               let mc = child.components[ModelComponent.self] {
                originalMaterials[child.name] = mc.materials
            }
            captureOriginalMaterials(from: child, regionKeys: regionKeys)
        }
    }

    /// Build box proxies for arm regions with clean vertical boundaries. Each
    /// region (shoulder → wrist_hand) gets its own Y-band box; the boundary
    /// between two adjacent regions is the midpoint of their mesh bounds so
    /// there is no overlap or gap. This is what makes "tap in the visible
    /// shoulder area" reliably resolve to shoulder — no convex-hull bloat.
    @MainActor
    private func createArmZoneProxies(for entity: Entity, regionKeys: Set<String>) {
        for side in ["left", "right"] {
            createArmZoneProxies(for: entity, side: side, regionKeys: regionKeys)
        }
    }

    @MainActor
    private func createArmZoneProxies(for entity: Entity, side: String, regionKeys: Set<String>) {
        let order = BodyMapConstants.armRegionOrder
        let zoneKeys = order.map { "\(side)_\($0)" }
        guard zoneKeys.allSatisfy(regionKeys.contains) else { return }
        let ents = zoneKeys.compactMap { entity.findEntity(named: $0) }
        guard ents.count == order.count else { return }
        let bounds = ents.map { $0.visualBounds(relativeTo: entity) }

        // Z = height in the model's root frame; bounds[0] (shoulder) is highest.
        // Arm region meshes OVERLAP each other significantly (elbow sits
        // entirely inside upper_arm's bounds; forearm's mesh extends upward
        // past elbow). Using min.z/max.z midpoints would produce inverted
        // zones. Use CENTER midpoints instead — always well-ordered.
        var transitions: [Float] = []
        for i in 0..<(order.count - 1) {
            transitions.append((bounds[i].center.z + bounds[i + 1].center.z) / 2)
        }

        for (i, zoneKey) in zoneKeys.enumerated() {
            let topZ = (i == 0) ? bounds[i].max.z : transitions[i - 1]
            let botZ = (i == order.count - 1) ? bounds[i].min.z : transitions[i]
            let zoneExtentZ = max(0.005, topZ - botZ)
            let zoneCenterZ = (topZ + botZ) / 2

            // Front-protrude so the box sits ahead of any torso/chest convex hull.
            let yFront = bounds[i].min.y - BodyMapConstants.armZoneForwardBias
            let yBack = bounds[i].max.y
            let zoneCenterY = (yFront + yBack) / 2
            let zoneExtentY = max(0.005, yBack - yFront)

            let zoneCenterX = bounds[i].center.x
            let zoneExtentX = max(0.005, bounds[i].extents.x)

            let proxy = Entity()
            proxy.name = BodyMapConstants.proxyPrefix + zoneKey
            proxy.position = SIMD3<Float>(zoneCenterX, zoneCenterY, zoneCenterZ)
            let shape = ShapeResource.generateBox(size: SIMD3<Float>(zoneExtentX, zoneExtentY, zoneExtentZ))
            proxy.components.set(CollisionComponent(shapes: [shape]))
            proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            entity.addChild(proxy)
        }
    }

    /// Build Y-banded box proxies for the lower-leg chain (calf_shin →
    /// ankle_foot). Mirrors `createArmZoneProxies`: midpoint transitions
    /// between mesh centers, forward-protruding, fully owns taps because
    /// the underlying convex hulls are disabled in `configureTemplateGeometry`.
    @MainActor
    private func createLegZoneProxies(for entity: Entity, regionKeys: Set<String>) {
        for side in ["left", "right"] {
            createLegZoneProxies(for: entity, side: side, regionKeys: regionKeys)
        }
    }

    @MainActor
    private func createLegZoneProxies(for entity: Entity, side: String, regionKeys: Set<String>) {
        let order = BodyMapConstants.lowerLegRegionOrder
        let zoneKeys = order.map { "\(side)_\($0)" }
        guard zoneKeys.allSatisfy(regionKeys.contains) else { return }
        let ents = zoneKeys.compactMap { entity.findEntity(named: $0) }
        guard ents.count == order.count else { return }
        let bounds = ents.map { $0.visualBounds(relativeTo: entity) }

        // Mesh-center midpoints — same logic as arms. Calf and ankle meshes
        // overlap along Z (the calf hull extends down past the ankle), so
        // using min.z/max.z would invert the boundary. Center midpoints stay
        // well-ordered.
        var transitions: [Float] = []
        for i in 0..<(order.count - 1) {
            transitions.append((bounds[i].center.z + bounds[i + 1].center.z) / 2)
        }

        // Calf_shin's mesh max.z extends up past the kneecap, so a naive
        // max.z top would eat the knee + lower-thigh tap area. Anchor at the
        // knee mesh's bottom instead — knee gets a real convex hull (it's not
        // in lowerLegRegionOrder, see configureTemplateGeometry), so capping
        // here cedes the upper band to that hull + the knee sphere proxy.
        let kneeBounds = entity.findEntity(named: "\(side)_knee")
            .map { $0.visualBounds(relativeTo: entity) }

        for (i, zoneKey) in zoneKeys.enumerated() {
            let topZ: Float
            if i == 0, let kneeBounds {
                topZ = min(bounds[i].max.z, kneeBounds.min.z + BodyMapConstants.calfShinKneeOverlap)
            } else if i == 0 {
                AppLogger.ui.warning("BodyMap3D: knee entity missing for side=\(side); calf_shin top falling back to bounds.max.z (calf_shin may bleed into kneecap)")
                topZ = bounds[i].max.z
            } else {
                topZ = transitions[i - 1]
            }
            let botZ = (i == order.count - 1) ? bounds[i].min.z : transitions[i]
            let zoneExtentZ = max(0.005, topZ - botZ)
            let zoneCenterZ = (topZ + botZ) / 2

            let yFront = bounds[i].min.y - BodyMapConstants.armZoneForwardBias
            let yBack = bounds[i].max.y
            let zoneCenterY = (yFront + yBack) / 2
            let zoneExtentY = max(0.005, yBack - yFront)

            let zoneCenterX = bounds[i].center.x
            let zoneExtentX = max(0.005, bounds[i].extents.x)

            let proxy = Entity()
            proxy.name = BodyMapConstants.proxyPrefix + zoneKey
            proxy.position = SIMD3<Float>(zoneCenterX, zoneCenterY, zoneCenterZ)
            let shape = ShapeResource.generateBox(size: SIMD3<Float>(zoneExtentX, zoneExtentY, zoneExtentZ))
            proxy.components.set(CollisionComponent(shapes: [shape]))
            proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            entity.addChild(proxy)
        }
    }

    /// Create invisible forward-protruding proxy entities for small regions.
    @MainActor
    private func createProxyEntities(for entity: Entity, regionKeys: Set<String>) {
        for zoneKey in regionKeys {
            let baseKey = BodyMapConstants.regionBaseKey(zoneKey)

            guard let radius = BodyMapConstants.proxyRadii[baseKey],
                  let regionEntity = entity.findEntity(named: zoneKey) else { continue }

            let bounds = regionEntity.visualBounds(relativeTo: entity)
            let center = bounds.center

            var proxyZ = center.z
            if baseKey == "knee" {
                proxyZ = bounds.min.z + bounds.extents.z * BodyMapConstants.kneeCapHeightFraction
            } else if baseKey == "head" {
                // Push head proxy up toward the top of the skull, away from the neck
                proxyZ = bounds.max.z - bounds.extents.z * 0.2
            }

            let proxyX = center.x

            // Regions that need extra forward bias to sit in front of adjacent regions
            let forwardBias: Float
            switch baseKey {
            case "head": forwardBias = 0.04
            default: forwardBias = BodyMapConstants.proxyForwardBias
            }

            let proxy = Entity()
            proxy.name = BodyMapConstants.proxyPrefix + zoneKey
            proxy.position = SIMD3<Float>(
                proxyX,
                bounds.min.y - forwardBias,
                proxyZ
            )

            let shape = ShapeResource.generateSphere(radius: radius)
            proxy.components.set(CollisionComponent(shapes: [shape]))

            proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            entity.addChild(proxy)
        }
    }

    // MARK: - Interaction Logic

    private func handleEntityTap(_ entity: Entity) {
        let name: String
        if entity.name.hasPrefix(BodyMapConstants.proxyPrefix) {
            name = String(entity.name.dropFirst(BodyMapConstants.proxyPrefix.count))
        } else {
            name = entity.name
        }

        guard viewModel.regions.contains(where: { $0.zoneKey == name }) else {
            return
        }

        if let zone = activeZone {
            // Drill-down mode: only respond to taps within the active zone
            guard zone.regionZoneKeys.contains(name) else { return }
            selectRegion(named: name)
        } else {
            // Overview mode: drill into the tapped entity's zone
            guard let zone = BodyZone.zone(for: name) else { return }
            drillIntoZone(zone)
        }
    }

    /// Toggle selection on a specific region (used in drill-down mode).
    private func selectRegion(named name: String) {
        guard let regionIndex = viewModel.regions.firstIndex(where: { $0.zoneKey == name }) else {
            return
        }

        let region = viewModel.regions[regionIndex]
        let wasSelected = region.isSelected

        let impact = UIImpactFeedbackGenerator(style: wasSelected ? .soft : .light)
        impact.impactOccurred()

        withAnimation(AppAnimations.springy) {
            viewModel.toggleSelection(for: region)
        }

        SessionLogger.shared.logUserAction(wasSelected ? .regionDeselected : .regionSelected,
                                            action: wasSelected ? "deselect" : "select",
                                            metadata: ["selectedCount": "\(viewModel.selectedRegions.count)"])

        if wasSelected {
            restoreMaterial(for: name)
        } else {
            applyHighlight(for: name)
        }

        withAnimation(.easeOut(duration: 0.2)) {
            lastTappedName = region.name
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.3)) {
                if lastTappedName == region.name {
                    lastTappedName = nil
                }
            }
        }
    }

    /// Toggle a region's selection from the inline zone drill-down region strip.
    private func toggleRegionInDrillDown(_ region: BodyRegion) {
        selectRegion(named: region.zoneKey)
    }

    // MARK: - Zone Drill-Down

    private func drillIntoZone(_ zone: BodyZone) {
        guard let pivot = pivotEntity else { return }

        cancelMomentum()
        rotationVelocity = 0

        // Look up camera target
        guard let target = BodyMapConstants.zoneCameraTargets[zone.rawValue] else { return }

        // Update accumulated state to match the drill-down position
        accumulatedScale = target.pivotScale
        accumulatedPanY = target.pivotY
        accumulatedRotation += target.rotation

        // Animate pivot to frame the zone
        var transform = pivot.transform
        transform.scale = SIMD3<Float>(repeating: target.pivotScale)
        transform.translation.x = target.pivotX
        transform.translation.y = target.pivotY
        transform.rotation = simd_quatf(angle: accumulatedRotation, axis: SIMD3<Float>(0, 1, 0))

        pivot.move(to: transform, relativeTo: pivot.parent,
                   duration: BodyMapConstants.zoneDrillDuration, timingFunction: .easeInOut)

        // Dim non-zone entities
        dimNonZoneEntities(zone: zone)

        // Repaint zone regions with per-zone palette so sub-regions are
        // instantly distinguishable. The wash returns on exit.
        applyZonePalette(for: zone)

        withAnimation(.easeInOut(duration: 0.3)) {
            activeZone = zone
            viewModel.activeZone = zone
        }

        // Show zone name toast
        withAnimation(.easeOut(duration: 0.2)) {
            lastTappedName = zone.displayName
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.3)) {
                if lastTappedName == zone.displayName {
                    lastTappedName = nil
                }
            }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        SessionLogger.shared.logUserAction(.regionSelected,
                                            action: "zone_drill_in",
                                            metadata: [:])
    }

    private func exitDrillDown() {
        guard let pivot = pivotEntity else { return }

        cancelMomentum()
        rotationVelocity = 0

        // Undo zone rotation
        if let zone = activeZone,
           let target = BodyMapConstants.zoneCameraTargets[zone.rawValue] {
            accumulatedRotation -= target.rotation
        }

        // Restore all dimmed entities
        restoreAllDimmedEntities()

        // Revert per-zone palette colors back to the unified wash so the
        // overview reads as the clean neutral mannequin again.
        if let zone = activeZone {
            revertZonePalette(for: zone)
        }

        // Animate back to overview
        accumulatedScale = 1.0
        accumulatedPanY = 0

        var transform = pivot.transform
        transform.scale = SIMD3<Float>(repeating: 1.0)
        transform.translation.x = 0
        transform.translation.y = 0
        transform.rotation = simd_quatf(angle: accumulatedRotation, axis: SIMD3<Float>(0, 1, 0))

        pivot.move(to: transform, relativeTo: pivot.parent,
                   duration: BodyMapConstants.zoneExitDuration, timingFunction: .easeInOut)

        withAnimation(.easeInOut(duration: 0.3)) {
            activeZone = nil
            viewModel.activeZone = nil
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        SessionLogger.shared.logUserAction(.regionDeselected,
                                            action: "zone_drill_out",
                                            metadata: [:])
    }

    // MARK: - Zone Dimming

    /// Hide all entities that don't belong to the active zone using isEnabled.
    private func dimNonZoneEntities(zone: BodyZone) {
        guard let body = bodyEntity else { return }
        let zoneKeys = Set(zone.regionZoneKeys)
        let keysToHide = Set(viewModel.regions.map(\.zoneKey)).subtracting(zoneKeys)

        hiddenEntityKeys = keysToHide
        setEntitiesEnabled(in: body, keys: keysToHide, enabled: false)
    }

    /// Restore all hidden entities.
    private func restoreAllDimmedEntities() {
        guard let body = bodyEntity else { return }

        setEntitiesEnabled(in: body, keys: hiddenEntityKeys, enabled: true)
        hiddenEntityKeys.removeAll()
    }

    /// Recursively enable/disable entities and their proxies matching the given keys.
    private func setEntitiesEnabled(in parent: Entity, keys: Set<String>, enabled: Bool) {
        for child in parent.children {
            if keys.contains(child.name) {
                child.isEnabled = enabled
            } else if child.name.hasPrefix(BodyMapConstants.proxyPrefix) {
                let regionKey = String(child.name.dropFirst(BodyMapConstants.proxyPrefix.count))
                if keys.contains(regionKey) {
                    child.isEnabled = enabled
                }
            }
            setEntitiesEnabled(in: child, keys: keys, enabled: enabled)
        }
    }

    /// Breadth-first walk the entity tree under `root` and return the first
    /// entity whose `name` matches AND that owns a `ModelComponent`. Works
    /// around the `body_model.usdz` structure where every region is an
    /// `Xform` parent with a same-named `Mesh` child — the stock
    /// `Entity.findEntity(named:)` would return the parent (no
    /// ModelComponent) and silently no-op every material mutation.
    private func findRenderableEntity(named name: String, in root: Entity) -> Entity? {
        var queue: [Entity] = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next.name == name, next.components[ModelComponent.self] != nil {
                return next
            }
            queue.append(contentsOf: next.children)
        }
        return nil
    }

    private func applyHighlight(for entityName: String) {
        guard let body = bodyEntity,
              let entity = findRenderableEntity(named: entityName, in: body) else { return }

        var material = SimpleMaterial()
        material.color = .init(tint: BodyMapConstants.highlightColor)
        material.roughness = .float(BodyMapConstants.highlightRoughness)
        material.metallic = .float(BodyMapConstants.highlightMetallic)

        if var mc = entity.components[ModelComponent.self] {
            mc.materials = [material]
            entity.components[ModelComponent.self] = mc
        }
    }

    private func restoreMaterial(for entityName: String) {
        guard let body = bodyEntity,
              let entity = findRenderableEntity(named: entityName, in: body),
              let origMats = originalMaterials[entityName],
              var mc = entity.components[ModelComponent.self] else { return }

        mc.materials = origMats
        entity.components[ModelComponent.self] = mc
    }

    private func clearAllSelections() {
        for region in viewModel.selectedRegions {
            restoreMaterial(for: region.zoneKey)
        }
        withAnimation(AppAnimations.springy) {
            viewModel.clearAll()
        }
    }

    private func resetView() {
        // If in drill-down, exit first (which animates back to overview)
        if activeZone != nil {
            exitDrillDown()
        }

        guard let pivot = pivotEntity else { return }

        cancelMomentum()
        rotationVelocity = 0

        accumulatedRotation = 0
        accumulatedScale = 1.0
        accumulatedPanY = 0
        resetGestureTracking()

        var target = Transform.identity
        target.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        target.scale = SIMD3<Float>(repeating: 1.0)
        target.translation.y = 0

        pivot.move(to: target, relativeTo: pivot.parent,
                   duration: 0.4, timingFunction: .easeInOut)
    }

    private func retryModelLoad() {
        loadError = nil
        isLoading = true
        // RealityView's make closure runs ONCE per view identity — the old comment
        // assumed it would re-execute on the next layout pass, so Retry cleared the
        // error, showed the spinner, and then nothing ever re-attempted the load.
        // Changing the identity is what forces a rebuild.
        modelReloadToken += 1
    }

    // MARK: - Zone Region Strip

    /// Horizontal scrollable strip of sub-region toggle buttons, shown below the 3D viewport during drill-down.
    private func zoneRegionStrip(zone: BodyZone) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(viewModel.regions(in: zone), id: \.id) { region in
                    Button(action: { toggleRegionInDrillDown(region) }) {
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(regionStripColor(for: region))
                                .frame(width: 8, height: 8)
                            Text(region.name)
                                .font(AppFonts.captionMedium)
                                .foregroundColor(AppColors.primaryText)
                            if region.isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(uiColor: BodyMapConstants.highlightColor))
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            region.isSelected
                                ? Color(uiColor: BodyMapConstants.highlightColor).opacity(0.25)
                                : AppColors.elevatedSurface.opacity(0.3)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .padding(.top, AppSpacing.sm)
    }

    private func regionStripColor(for region: BodyRegion) -> Color {
        let baseKey = BodyMapConstants.regionBaseKey(region.zoneKey)
        // In drill-down, mirror the zone palette so the pill dots match the
        // mannequin's color-coded sub-regions one-to-one.
        if let zone = activeZone,
           let color = BodyMapConstants.zoneColor(zone: zone, baseKey: baseKey) {
            return Color(uiColor: color)
        }
        if let color = BodyMapConstants.regionColors[baseKey] {
            return Color(uiColor: color)
        }
        return AppColors.mutedText
    }

    // MARK: - Zone Palette Painting

    /// Paint each region in the active zone with its per-zone palette color.
    /// Also updates `originalMaterials` for these regions so a later
    /// selection → deselection cycle restores to the palette color rather
    /// than the wash. Called from `drillIntoZone`.
    ///
    /// Currently-selected regions keep their teal highlight on screen;
    /// only their stored `originalMaterials` entry is updated to the palette
    /// color so a future deselect lands on the palette, not the stale wash.
    @MainActor
    private func applyZonePalette(for zone: BodyZone) {
        guard let body = bodyEntity else {
            AppLogger.ui.warning("BodyMap3D: applyZonePalette zone=\(zone.rawValue) but bodyEntity is nil")
            return
        }
        let selectedKeys = Set(viewModel.selectedRegions.map(\.zoneKey))

        for zoneKey in zone.regionZoneKeys {
            let baseKey = BodyMapConstants.regionBaseKey(zoneKey)
            guard let color = BodyMapConstants.zoneColor(zone: zone, baseKey: baseKey) else {
                AppLogger.ui.warning("BodyMap3D: no zone color for zone=\(zone.rawValue) baseKey=\(baseKey)")
                continue
            }

            // Bilateral pairs: paint both left_ and right_ variants if they exist.
            for fullKey in entityKeys(forBaseKey: baseKey, zoneKey: zoneKey) {
                if selectedKeys.contains(fullKey) {
                    // Preserve the red highlight visually; just update the
                    // "original" material so deselect later reverts to palette.
                    storeOriginalMaterial(named: fullKey, with: color)
                } else {
                    paintEntity(named: fullKey, in: body, with: color)
                }
            }
        }
    }

    /// Revert every region in the given zone back to the unified wash color
    /// from `regionColors`. Restores `originalMaterials` to match so future
    /// deselects after a re-drill don't flash the stale palette material.
    /// Called from `exitDrillDown`.
    ///
    /// Currently-selected regions keep their teal highlight on screen;
    /// only their stored `originalMaterials` entry is updated to the wash so
    /// a future deselect lands on the wash, not the stale palette color.
    @MainActor
    private func revertZonePalette(for zone: BodyZone) {
        guard let body = bodyEntity else { return }
        let selectedKeys = Set(viewModel.selectedRegions.map(\.zoneKey))

        for zoneKey in zone.regionZoneKeys {
            let baseKey = BodyMapConstants.regionBaseKey(zoneKey)
            guard let washColor = BodyMapConstants.regionColors[baseKey] else { continue }

            for fullKey in entityKeys(forBaseKey: baseKey, zoneKey: zoneKey) {
                if selectedKeys.contains(fullKey) {
                    storeOriginalMaterial(named: fullKey, with: washColor)
                } else {
                    paintEntity(named: fullKey, in: body, with: washColor)
                }
            }
        }
    }

    /// Enumerate the actual entity name(s) for a base key. Bilateral regions
    /// (those whose zoneKey starts with `left_` or `right_`) live on the model
    /// as `left_<base>` AND `right_<base>` — repaint both. Non-bilateral
    /// regions (head, neck, chest, abdomen, upper_back, lower_back) live as
    /// just `<base>`.
    private func entityKeys(forBaseKey baseKey: String, zoneKey: String) -> [String] {
        if zoneKey.hasPrefix("left_") || zoneKey.hasPrefix("right_") {
            return ["left_\(baseKey)", "right_\(baseKey)"]
        }
        return [baseKey]
    }

    /// Paint a single entity with a flat material in the given color, and
    /// update `originalMaterials` so that subsequent select→deselect
    /// restores to this color, not the prior one.
    @MainActor
    private func paintEntity(named name: String, in body: Entity, with color: UIColor) {
        guard let entity = findRenderableEntity(named: name, in: body) else { return }

        let material = makeRegionMaterial(color: color)

        if var mc = entity.components[ModelComponent.self] {
            mc.materials = [material]
            entity.components[ModelComponent.self] = mc
            // Re-sync the "original" material so deselect after select restores
            // to whatever we last painted (palette during drill-down, wash on exit).
            originalMaterials[name] = [material]
        }
    }

    /// Store the "original" material for a region without touching its
    /// currently-rendered material. Used for regions whose highlight (red
    /// selection material) must remain visible — we only need a future
    /// deselect to land on the new color, not change what's drawn now.
    @MainActor
    private func storeOriginalMaterial(named name: String, with color: UIColor) {
        originalMaterials[name] = [makeRegionMaterial(color: color)]
    }

    /// Build the standard region material (matte, slight specular) for a color.
    private func makeRegionMaterial(color: UIColor) -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = .float(BodyMapConstants.regionRoughness)
        material.metallic = .float(BodyMapConstants.regionMetallic)
        return material
    }

    // MARK: - Region Color Coding

    private func applyRegionColor(to entity: Entity) {
        let baseKey = BodyMapConstants.regionBaseKey(entity.name)
        guard let color = BodyMapConstants.regionColors[baseKey] else { return }

        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = .float(BodyMapConstants.regionRoughness)
        material.metallic = .float(BodyMapConstants.regionMetallic)

        if var mc = entity.components[ModelComponent.self] {
            mc.materials = [material]
            entity.components[ModelComponent.self] = mc
        }
    }
}
