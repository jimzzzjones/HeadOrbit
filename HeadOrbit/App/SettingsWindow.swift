import SwiftUI

@MainActor
final class SettingsWindow {
    private static var window: NSWindow?

    static func show(tracker: HeadTracker, blur: LookAwayBlurAction, posture: PostureReminderAction) {
        let view = MenuView().environmentObject(tracker).environmentObject(blur).environmentObject(posture)
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 760),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        panel.title = "HeadOrbit"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = panel
    }
}
