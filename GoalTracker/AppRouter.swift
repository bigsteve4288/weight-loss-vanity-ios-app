import Observation

enum AppTab: Hashable {
    case dashboard, transform, mindset, plan
}

/// App-wide navigation, so tapping a check-in notification can open the Check-ins list.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .dashboard
    var isShowingCheckIns = false

    func openCheckIns() {
        tab = .mindset
        isShowingCheckIns = true
    }
}
