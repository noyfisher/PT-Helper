import SwiftUI

/// The primary navigation container: 4 tabs (Home · My Plan · Progress · Profile)
/// plus a floating "+" that opens the assessment gateway.
struct MainTabView: View {
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var savedPlansViewModel = SavedPlansViewModel()
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var recoveryInsightsViewModel = RecoveryInsightsViewModel()
    @StateObject private var analysisStore = AnalysisResultStore.shared

    /// Set by RootView when the user finishes onboarding, so completing their
    /// profile hands them straight into their first assessment (the "aha" moment)
    /// rather than dropping them cold on the Home tab. Consumed once on appear.
    @AppStorage("pendingFirstAssessment") private var pendingFirstAssessment = false

    /// Reusable offline banner — shown in the tab container AND inside the
    /// assessment cover, since the cover overlays the container and hides the
    /// container's banner during the one flow most dependent on connectivity (#59).
    @ViewBuilder
    private var offlineBanner: some View {
        if !networkMonitor.isConnected {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12, weight: .semibold))
                Text("You're offline. Changes will sync when reconnected.")
                    .font(AppFonts.caption)
            }
            .foregroundColor(AppColors.ctaText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.danger)
            .accessibilityIdentifier("offlineBanner")
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                offlineBanner

                TabView(selection: $tabSelection.selectedTab) {
                    HomeTab()
                        .tag(0)
                        .id(tabSelection.assessNavigationId)
                        .toolbar(.hidden, for: .tabBar)

                    MyPlanTab()
                        .tag(1)
                        .id(tabSelection.myPlanNavigationId)
                        .toolbar(.hidden, for: .tabBar)

                    ProgressTab()
                        .tag(2)
                        .id(tabSelection.progressNavigationId)
                        .toolbar(.hidden, for: .tabBar)

                    ProfileTab()
                        .tag(3)
                        .id(tabSelection.profileNavigationId)
                        .toolbar(.hidden, for: .tabBar)
                }
            }

            // Full-width tab bar pinned to bottom
            VStack(spacing: 0) {
                Spacer()
                FloatingTabBar(selectedTab: $tabSelection.selectedTab, onTabTapped: { tapped in
                    if tabSelection.selectedTab == tapped {
                        tabSelection.popToRootCurrentTab()
                    }
                }, onAssessmentTapped: {
                    tabSelection.assessmentRequest = .gateway
                })
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .environmentObject(tabSelection)
        .environmentObject(savedPlansViewModel)
        .environmentObject(workoutViewModel)
        .environmentObject(networkMonitor)
        .environmentObject(recoveryInsightsViewModel)
        .environmentObject(analysisStore)
        .onChange(of: tabSelection.selectedTab) { _, newTab in
            // No re-tap branch here: onChange only fires when the value actually
            // changes, so `oldTab == newTab` was unreachable and read as though
            // pop-to-root-on-retap lived here. It is implemented in the tab bar's
            // own tap handler, which can see a tap on the already-selected tab.
            let tabNames = ["Home", "My Plan", "Progress", "Profile"]
            let name = newTab < tabNames.count ? tabNames[newTab] : "Unknown"
            SessionLogger.shared.logNavigation(.tabSwitched, screen: name, metadata: ["tab": "\(newTab)"])
            AnalyticsService.shared.log(.tabSwitched, parameters: ["tab_index": newTab])
        }
        .fullScreenCover(item: $tabSelection.assessmentRequest) { route in
            VStack(spacing: 0) {
                offlineBanner
                NavigationStack {
                    assessmentDestination(for: route)
                    .toolbar {
                        // The destinations register navigationDestinations, so the
                        // close affordance lives out here and toggles state directly
                        // instead of reading @Environment(\.dismiss) (P1 freeze class).
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                tabSelection.assessmentRequest = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("bodyMap.closeButton")
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { _ in
            tabSelection.assessmentRequest = nil
            tabSelection.popToRootAndGoHome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLink)) { _ in
            handleDeepLink()
        }
        .onAppear {
            applyCoilNavBarAppearance()
            handleDeepLink()
            // Post-onboarding hand-off: route straight into the first assessment.
            if pendingFirstAssessment {
                pendingFirstAssessment = false
                tabSelection.assessmentRequest = .gateway
            }
        }
    }

    // MARK: - Assessment presentation

    /// The screen shown inside the assessment `fullScreenCover` for a given route.
    @ViewBuilder
    private func assessmentDestination(for route: AssessmentRoute) -> some View {
        switch route {
        case .gateway:
            AssessmentGatewayView()
        case .pain:
            BodyMap3DView()
        case .wellness:
            if let profile = UserProfileService.shared.profile {
                WellnessGoalPickerView(userProfile: profile)
            } else {
                // No profile (skipped onboarding) — fall back to the chooser.
                AssessmentGatewayView()
            }
        }
    }

    /// Routes a pending notification deep link. "analyze"/"wellness" now open the
    /// assessment gateway/wellness picker (previously "analyze" dead-ended on the
    /// Home tab), keeping the routing table aligned with real tab contents.
    private func handleDeepLink() {
        guard let tab = NotificationService.shared.pendingDeepLink else { return }
        switch tab {
        case "home": tabSelection.selectedTab = 0
        case "analyze": tabSelection.assessmentRequest = .gateway
        case "wellness": tabSelection.assessmentRequest = .wellness
        case "plans", "rehab": tabSelection.selectedTab = 1
        case "progress": tabSelection.selectedTab = 2
        case "profile": tabSelection.selectedTab = 3
        default: break
        }
        NotificationService.shared.pendingDeepLink = nil
    }

    // MARK: - COIL UIKit Appearance (nav bar only — tab bar is custom)

    private func applyCoilNavBarAppearance() {
        // Nav bar is fixed dark brand chrome in both appearances. Source colors from
        // the Tier-0 CoilPalette primitives directly (dynamic UIColor) rather than
        // round-tripping a SwiftUI Color, which would flatten to a launch-time snapshot.
        let navBgColor = CoilPalette.ink

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = navBgColor
        navBar.shadowColor = UIColor(AppColors.navBorder)
        let titleFont = UIFont(name: "Industry-Bold", size: 19)
            ?? UIFont.systemFont(ofSize: 19, weight: .black)
        let largeTitleFont = UIFont(name: "Industry-Bold", size: 28)
            ?? UIFont.systemFont(ofSize: 28, weight: .black)
        navBar.titleTextAttributes = [.foregroundColor: UIColor.white, .font: titleFont]
        navBar.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: largeTitleFont]
        let backImage = UIImage(systemName: "chevron.left")?
            .withTintColor(CoilPalette.accent, renderingMode: .alwaysOriginal)
        navBar.setBackIndicatorImage(backImage, transitionMaskImage: backImage)
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().tintColor = CoilPalette.accent
    }
}

// MARK: - Profile Tab

struct ProfileTab: View {
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            SettingsView(
                userName: UserProfileService.shared.profile?.firstName ?? "User",
                onEditProfile: { showEditProfile = true }
            )
        }
        .sheet(isPresented: $showEditProfile) {
            // Real editor (matches the ProgressTab path) — was a placeholder stub.
            OnboardingEditView()
        }
    }
}

// MARK: - Tab Bar

/// Layout metrics for the custom `FloatingTabBar`.
enum FloatingTabBarMetrics {
    /// Bottom clearance needed so on-screen content/footers sit above the
    /// floating tab bar. The bar overlays the bottom of every view rendered
    /// inside the tab navigation (it lives in `MainTabView`'s ZStack, outside
    /// the NavigationStacks, and uses `.ignoresSafeArea(edges: .bottom)`), so
    /// this covers the full bar footprint including the home-indicator area and
    /// the lifted centre "+" button.
    static let clearance: CGFloat = 100
}

extension View {
    /// Adds bottom padding so content/footers clear the custom `FloatingTabBar`
    /// overlay. Apply to a pinned footer's bottom or to a ScrollView's inner
    /// content container.
    func floatingTabBarClearance() -> some View {
        padding(.bottom, FloatingTabBarMetrics.clearance)
    }
}

private struct TabBarItem {
    let tag: Int
    let icon: String
    let label: String
}

/// Left pair and right pair flank the centre "+" button.
private let leftTabItems: [TabBarItem] = [
    TabBarItem(tag: 0, icon: "house.fill",         label: "Home"),
    TabBarItem(tag: 1, icon: "list.clipboard.fill", label: "Plan"),
]
private let rightTabItems: [TabBarItem] = [
    TabBarItem(tag: 2, icon: "chart.line.uptrend.xyaxis", label: "Progress"),
    TabBarItem(tag: 3, icon: "person.fill",               label: "Profile"),
]

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    var onTabTapped: (Int) -> Void
    var onAssessmentTapped: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // ── Full-width bar ─────────────────────────────────────────────
            HStack(spacing: 0) {
                // Left tabs
                ForEach(leftTabItems, id: \.tag) { item in
                    tabButton(item)
                }

                // Centre spacer — reserves room beneath the "+" button
                Spacer()
                    .frame(width: 72)

                // Right tabs
                ForEach(rightTabItems, id: \.tag) { item in
                    tabButton(item)
                }
            }
            .padding(.top, AppSpacing.comfortable)   // push tab icons down below the "+" button
            .frame(maxWidth: .infinity)
            .background(AppColors.navBackground)

            // ── Big "+" button centred, lifts above the bar ───────────────
            Button {
                // Tactile feedback on the app's primary action (audit #77).
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onAssessmentTapped()
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 56, height: 56)
                            .shadow(color: AppColors.accent.opacity(0.5), radius: 10, x: 0, y: -4)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    // Visible caption so the app's most important action reads as
                    // "start a pain/wellness assessment", not a generic "add item".
                    Text("Assess")
                        .font(AppFonts.microMedium)
                        .foregroundColor(AppColors.accent)
                }
            }
            .accessibilityLabel("New Assessment")
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(y: -8)   // lift slightly above the bar top edge
        }
    }

    @ViewBuilder
    private func tabButton(_ item: TabBarItem) -> some View {
        Button {
            // Light selection haptic + animated active-color change (audit #77).
            UISelectionFeedbackGenerator().selectionChanged()
            onTabTapped(item.tag)
            selectedTab = item.tag
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(item.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(selectedTab == item.tag ? AppColors.tabActive : AppColors.tabInactive)
            .animation(AppAnimations.smooth, value: selectedTab)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.comfortable)
        }
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selectedTab == item.tag ? [.isSelected] : [])
    }
}
