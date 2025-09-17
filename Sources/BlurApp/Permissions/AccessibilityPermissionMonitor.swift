import ApplicationServices
import Foundation

@MainActor
final class AccessibilityPermissionMonitor {
    private var timer: DispatchSourceTimer?

    var isAuthorized: Bool {
        AXIsProcessTrusted()
    }

    func requestAuthorizationPrompt() {
        // Avoid referencing the non-Sendable CF global `kAXTrustedCheckOptionPrompt` directly.
        // The documented key string for this option is "AXTrustedCheckOptionPrompt".
        let options: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func startMonitoring(interval: TimeInterval = 1.5, handler: @escaping (Bool) -> Void) {
        stopMonitoring()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            handler(self.isAuthorized)
        }
        self.timer = timer
        timer.resume()
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }
}

