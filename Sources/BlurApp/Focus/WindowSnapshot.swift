import CoreGraphics

struct WindowSnapshot: Hashable {
    let windowID: CGWindowID
    let frame: CGRect
    let screenID: CGDirectDisplayID
    let appBundleIdentifier: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(screenID)
        hasher.combine(frame)
    }

    static func == (lhs: WindowSnapshot, rhs: WindowSnapshot) -> Bool {
        lhs.windowID == rhs.windowID && lhs.screenID == rhs.screenID && lhs.frame == rhs.frame
    }
}
