import AppKit

@main
enum BlurAppMain {
    static func main() {
        if Thread.isMainThread {
            startBlurApp()
        } else {
            DispatchQueue.main.sync {
                startBlurApp()
            }
        }
    }
}
