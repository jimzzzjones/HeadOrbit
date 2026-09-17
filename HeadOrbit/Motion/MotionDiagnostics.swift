import AppKit
import UniformTypeIdentifiers

final class MotionDiagnostics {
    struct Row {
        var time: TimeInterval
        var sensorTime: TimeInterval
        var epoch: Int
        var rawYaw: Double
        var yaw: Double
        var rawPitch: Double
        var rawRoll: Double
        var rotationX: Double
        var rotationY: Double
        var rotationZ: Double
        var acceleration: Double
        var side: Int
        var yawValid: Bool
        var postureValid: Bool
        var mode: String
        var activityAge: Double? = nil
        var recoveryReason: String = ""
        var recoveryWindows: Int = 0
        var relativePitch: Double? = nil
        var referenceSource: String = "none"
    }

    private(set) var rows: [Row] = []

    func record(_ row: Row) {
        if let previous = rows.last, row.time - previous.time < 0.1 { return }
        rows.removeAll { row.time - $0.time > 120 }
        rows.append(row)
    }

    func csv() -> String {
        let first = rows.first?.time ?? 0
        var result = "elapsed_s,sensor_time_s,epoch,raw_yaw_deg,relative_yaw_deg,raw_pitch_deg,raw_roll_deg,rotation_x_deg_s,rotation_y_deg_s,rotation_z_deg_s,acceleration_g,sensor_side,yaw_valid,posture_valid,calibration,activity_age_s,recovery_reason,completed_windows,relative_pitch_deg,reference_source\n"
        for row in rows {
            let values = [row.time - first, row.sensorTime, row.rawYaw, row.yaw, row.rawPitch,
                          row.rawRoll, row.rotationX, row.rotationY, row.rotationZ, row.acceleration]
                .map { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), $0) }
            let activity = row.activityAge.map { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            let pitch = row.relativePitch.map { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            result += ([values[0], values[1], String(row.epoch)] + Array(values.dropFirst(2)) +
                       [String(row.side), row.yawValid ? "1" : "0", row.postureValid ? "1" : "0", row.mode,
                        activity, row.recoveryReason, String(row.recoveryWindows), pitch, row.referenceSource]).joined(separator: ",") + "\n"
        }
        return result
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "HeadOrbit-motion-\(Int(Date().timeIntervalSince1970)).csv"
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try csv().write(to: url, atomically: true, encoding: .utf8) }
        catch { NSAlert(error: error).runModal() }
    }
}
