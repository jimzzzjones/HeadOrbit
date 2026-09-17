import AppKit
import CoreGraphics

enum InteractionSignal {
    static func latest(at now: TimeInterval) -> TimeInterval? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != "com.apple.loginwindow",
              app.bundleIdentifier != "com.apple.ScreenSaver.Engine" else { return nil }
        // Only event age is queried. No key contents, event taps or input-monitoring permission.
        let ages = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel].map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.filter { $0.isFinite && $0 >= 0 }
        guard let age = ages.min(), age <= 1 else { return nil }
        return now - age
    }
}
