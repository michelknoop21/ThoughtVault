import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "NetworkMonitor")

// MARK: - NetworkMonitor

/// Monitors network connectivity using the Network framework.
/// Publishes connectivity status changes and fires a callback when connectivity is restored.
@Observable
final class NetworkMonitor: @unchecked Sendable {

    static let shared = NetworkMonitor()

    // MARK: - Observable State

    private(set) var isConnected: Bool = true

    // MARK: - Callbacks

    /// Called on the main thread when network connectivity is restored after being offline.
    var onConnectivityRestored: (() -> Void)?

    // MARK: - Private

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "nl.prezent.TranscriptStudio.NetworkMonitor", qos: .utility)

    // MARK: - Init

    private init() {
        monitor = NWPathMonitor()
        start()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Monitoring

    private func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let nowConnected = path.status == .satisfied

            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = nowConnected

                if nowConnected && !wasConnected {
                    logger.info("NetworkMonitor: connectivity restored")
                    self.onConnectivityRestored?()
                } else if !nowConnected && wasConnected {
                    logger.info("NetworkMonitor: connectivity lost")
                }
            }
        }

        monitor.start(queue: monitorQueue)
        logger.info("NetworkMonitor: started monitoring")
    }
}
