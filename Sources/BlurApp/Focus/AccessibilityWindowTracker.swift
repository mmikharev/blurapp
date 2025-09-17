import AppKit
import ApplicationServices
import QuartzCore

// Some SDKs don't surface this constant in Swift headers. Define it here.
private let kAXWindowNumberAttribute: String = "AXWindowNumber"

// Fallbacks for AX constants that may be missing from some Swift headers.
private let kAXBundleIdentifierAttribute: String = "AXBundleIdentifier"
private let kAXSheetSubrole: String = "AXSheet"

final class AccessibilityWindowTracker {
    private let systemWideElement = AXUIElementCreateSystemWide()
    private var lastHoveredWindow: WindowSnapshot?
    private var lastHoverTimestamp: CFTimeInterval = 0
    private let followMouseHysteresis: CFTimeInterval = 0.20

    func focusedWindows(
        configuration: FocusConfiguration,
        exclusions: Set<String>
    ) -> [WindowSnapshot] {
        guard AXIsProcessTrusted() else { return [] }
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return [] }

        if let bundleID = frontmostApp.bundleIdentifier, exclusions.contains(bundleID) {
            return []
        }

        let bundleIdentifier = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        if configuration.followMouse {
            if let hoveredWindow = windowUnderCursor(exclusions: exclusions) {
                let now = CACurrentMediaTime()
                if let last = lastHoveredWindow, last.windowID == hoveredWindow.windowID {
                    lastHoveredWindow = hoveredWindow
                    lastHoverTimestamp = now
                    return [hoveredWindow]
                }

                if now - lastHoverTimestamp >= followMouseHysteresis {
                    lastHoveredWindow = hoveredWindow
                    lastHoverTimestamp = now
                    return [hoveredWindow]
                }

                if let last = lastHoveredWindow {
                    return [last]
                } else {
                    lastHoveredWindow = hoveredWindow
                    lastHoverTimestamp = now
                    return [hoveredWindow]
                }
            } else if let last = lastHoveredWindow {
                let now = CACurrentMediaTime()
                if now - lastHoverTimestamp < followMouseHysteresis {
                    return [last]
                }
            }
        }

        switch configuration.mode {
        case .activeApp:
            return windows(
                for: appElement,
                bundleIdentifier: bundleIdentifier,
                exclusions: exclusions
            )
        case .activeWindow:
            if let focused = focusedWindow(
                for: appElement,
                bundleIdentifier: bundleIdentifier,
                exclusions: exclusions
            ) {
                return [focused]
            }
            if let first = windows(
                for: appElement,
                bundleIdentifier: bundleIdentifier,
                exclusions: exclusions
            ).first {
                return [first]
            }
            return []
        }
    }

    private func windows(
        for appElement: AXUIElement,
        bundleIdentifier: String?,
        exclusions: Set<String>
    ) -> [WindowSnapshot] {
        guard let windowElements = copyAttributeValues(element: appElement, attribute: kAXWindowsAttribute) else {
            return []
        }

        return windowElements.compactMap { element in
            guard let bundleID = bundleIdentifier ?? enclosingBundleIdentifier(for: element) else { return nil }
            guard !exclusions.contains(bundleID) else { return nil }
            return createSnapshot(for: element, bundleIdentifier: bundleID)
        }
    }

    private func focusedWindow(
        for appElement: AXUIElement,
        bundleIdentifier: String?,
        exclusions: Set<String>
    ) -> WindowSnapshot? {
        guard let element: AXUIElement = copyAttributeValue(element: appElement, attribute: kAXFocusedWindowAttribute) else {
            return nil
        }
        guard let bundleID = bundleIdentifier ?? enclosingBundleIdentifier(for: element) else { return nil }
        guard !exclusions.contains(bundleID) else { return nil }
        return createSnapshot(for: element, bundleIdentifier: bundleID)
    }

    private func windowUnderCursor(exclusions: Set<String>) -> WindowSnapshot? {
        let mouseLocation = NSEvent.mouseLocation
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(mouseLocation.x), Float(mouseLocation.y), &hitElement)
        guard result == .success, let element = hitElement else {
            return nil
        }

        var current: AXUIElement? = element
        var iteration = 0
        while let candidate = current, iteration < 8 {
            iteration += 1
            if let snapshot = snapshotIfWindow(candidate, exclusions: exclusions) {
                return snapshot
            }
            current = copyAttributeValue(element: candidate, attribute: kAXParentAttribute)
        }
        return nil
    }

    private func snapshotIfWindow(_ element: AXUIElement, exclusions: Set<String>) -> WindowSnapshot? {
        guard let role: String = copyAttributeValue(element: element, attribute: kAXRoleAttribute) else {
            return nil
        }
        guard role == (kAXWindowRole as String) else { return nil }
        guard let bundleID = enclosingBundleIdentifier(for: element) else { return nil }
        guard !exclusions.contains(bundleID) else { return nil }
        return createSnapshot(for: element, bundleIdentifier: bundleID)
    }

    private func createSnapshot(for element: AXUIElement, bundleIdentifier: String) -> WindowSnapshot? {
        guard isStandardWindow(element: element) else { return nil }
        guard let frame = fetchFrame(for: element) else { return nil }
        guard let screenID = screenIdentifier(for: frame) else { return nil }
        guard let windowNumber: Int = copyAttributeValue(element: element, attribute: kAXWindowNumberAttribute) else { return nil }

        return WindowSnapshot(
            windowID: CGWindowID(windowNumber),
            frame: frame,
            screenID: screenID,
            appBundleIdentifier: bundleIdentifier
        )
    }

    private func enclosingBundleIdentifier(for element: AXUIElement) -> String? {
        if let bundle: String = copyAttributeValue(element: element, attribute: kAXBundleIdentifierAttribute) {
            return bundle
        }

        if let appElement: AXUIElement = copyAttributeValue(element: element, attribute: kAXParentAttribute) {
            if let role: String = copyAttributeValue(element: appElement, attribute: kAXRoleAttribute), role == (kAXApplicationRole as String) {
                return copyAttributeValue(element: appElement, attribute: kAXBundleIdentifierAttribute)
            }
            return enclosingBundleIdentifier(for: appElement)
        }

        return nil
    }

    private func isStandardWindow(element: AXUIElement) -> Bool {
        guard let subrole: String = copyAttributeValue(element: element, attribute: kAXSubroleAttribute) else {
            return true
        }
        let excludedSubroles: Set<String> = [
            kAXSystemDialogSubrole as String,
            kAXFloatingWindowSubrole as String,
            kAXSheetSubrole as String,
            "AXPopover"
        ]
        return !excludedSubroles.contains(subrole)
    }

    private func fetchFrame(for element: AXUIElement) -> CGRect? {
        guard
            let positionValue: AXValue = copyAttributeValue(element: element, attribute: kAXPositionAttribute),
            let sizeValue: AXValue = copyAttributeValue(element: element, attribute: kAXSizeAttribute)
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    private func screenIdentifier(for windowFrame: CGRect) -> CGDirectDisplayID? {
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            if screen.frame.intersects(windowFrame) {
                return displayID
            }
        }
        return NSScreen.main?.displayID
    }

    private func copyAttributeValue<T>(element: AXUIElement, attribute: String) -> T? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard result == .success, let value = ref as? T else { return nil }
        return value
    }

    private func copyAttributeValues(element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard result == .success else { return nil }
        return ref as? [AXUIElement]
    }
}

