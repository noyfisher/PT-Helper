import SwiftUI

/// Which assessment entry to present from the floating "+" or a CTA button.
enum AssessmentRoute: Int, Identifiable {
    case gateway   // dual choice: "Something hurts" vs "Improve my life"
    case pain      // straight into the body-map pain assessment
    case wellness  // straight into the wellness goal picker
    var id: Int { rawValue }
}

/// Observable class to allow any child view to switch tabs or pop to root
class TabSelection: ObservableObject {
    @Published var selectedTab: Int = 0

    /// Set by any child tab / CTA to request an assessment entry point.
    /// `MainTabView` observes this and presents the matching full-screen cover,
    /// so buttons no longer dead-end on `selectedTab = 0` (the Home tab, which has
    /// no assessment launcher).
    @Published var assessmentRequest: AssessmentRoute?

    @Published var progressNavigationId = UUID()

    @Published var profileNavigationId = UUID()

    /// Navigation IDs for the tab layout (Home / My Plan / Progress / Profile).
    @Published var assessNavigationId = UUID()
    @Published var myPlanNavigationId = UUID()

    func popToRootAndGoHome() {
        if selectedTab == 0 {
            assessNavigationId = UUID()
            return
        }
        switch selectedTab {
        case 1: myPlanNavigationId = UUID()
        case 2: progressNavigationId = UUID()
        case 3: profileNavigationId = UUID()
        default: break
        }
        selectedTab = 0
    }

    /// Pop to root on the current tab (used when re-tapping the active tab).
    func popToRootCurrentTab() {
        switch selectedTab {
        case 0: assessNavigationId = UUID()
        case 1: myPlanNavigationId = UUID()
        case 2: progressNavigationId = UUID()
        case 3: profileNavigationId = UUID()
        default: break
        }
    }
}
