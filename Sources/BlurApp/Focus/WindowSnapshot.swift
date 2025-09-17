import CoreGraphics

struct WindowSnapshot: Hashable {
    let windowID: CGWindowID
    let frame: CGRect
    let screenID: CGDirectDisplayID
    let appBundleIdentifier: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(screenID)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
    }

    static func == (lhs: WindowSnapshot, rhs: WindowSnapshot) -> Bool {
        return
            lhs.windowID == rhs.windowID &&
            lhs.screenID == rhs.screenID &&
            lhs.frame.origin.x == rhs.frame.origin.x &&
            lhs.frame.origin.y == rhs.frame.origin.y &&
            lhs.frame.size.width == rhs.frame.size.width &&
            lhs.frame.size.height == rhs.frame.size.height
    }
}
