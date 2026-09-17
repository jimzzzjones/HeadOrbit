import SwiftUI

@main
struct HeadOrbitApp: App {
    @StateObject private var tracker: HeadTracker
    @StateObject private var blurAction: LookAwayBlurAction
    @StateObject private var postureAction: PostureReminderAction
    @StateObject private var engine: ActionEngine

    init() {
        let tracker = HeadTracker()
        let blur = LookAwayBlurAction()
        let posture = PostureReminderAction()
        let engine = ActionEngine(tracker: tracker, actions: [blur, posture])
        _tracker = StateObject(wrappedValue: tracker)
        _blurAction = StateObject(wrappedValue: blur)
        _postureAction = StateObject(wrappedValue: posture)
        _engine = StateObject(wrappedValue: engine)
        tracker.start()
        L10n.shared.applyAppearance()
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async {
                SettingsWindow.show(tracker: tracker, blur: blur, posture: posture)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(tracker)
                .environmentObject(blurAction)
                .environmentObject(postureAction)
        } label: {
            HStack(spacing: 2) {
                Image(nsImage: tracker.status.isTracking ? MenuBarIcon.connected : MenuBarIcon.disconnected)
                if tracker.status.isTracking && !tracker.isCalibrated {
                    Circle().fill(.orange).frame(width: 4, height: 4)
                }
            }
            .accessibilityLabel("HeadOrbit")
        }
        .menuBarExtraStyle(.window)
    }
}
