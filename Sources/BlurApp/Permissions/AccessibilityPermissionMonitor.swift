import ApplicationServices
import Foundation

final class AccessibilityPermissionMonitor {
    private var timer: DispatchSourceTimer?

    var isAuthorized: Bool {
        AXIsProcessTrusted()
    }

    func requestAuthorizationPrompt() {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
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
