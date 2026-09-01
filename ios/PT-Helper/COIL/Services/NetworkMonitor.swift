import Foundation
import Network
import Combine

/// Monitors network connectivity and publishes status changes.
/// Used to show an offline banner and enable graceful degradation.
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected: Bool = true
    @Published var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi, cellular, wired, unknown
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.pthealer.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                // `--simulate-offline` seeds isConnected = false, but NWPathMonitor's
                // first update lands asynchronously and used to overwrite it — so the
                // offline UI-test scenario silently ran online and the offline paths
                // it exists to cover were never exercised. (Debug-only: the flag is
                // #if DEBUG and reads false in release.)
                guard !TestDataSeeder.shouldSimulateOffline else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied

                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = .wired
                } else {
                    self.connectionType = .unknown
                }

                if wasConnected != self.isConnected {
                    SessionLogger.shared.log(.connectivityChanged, category: .system,
                                              message: self.isConnected ? "Connected" : "Disconnected",
                                              metadata: ["connected": "\(self.isConnected)",
                                                          "type": self.connectionType.description])
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
