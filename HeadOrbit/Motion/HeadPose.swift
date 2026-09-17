import CoreMotion
import Foundation

/// 一帧头部姿态，角度单位为「度」，已经减去校准基准（校准后正对屏幕时三项都≈0）。
struct HeadPose: Equatable {
    var yaw: Double     // 左右转头。已取反成「向右转为正」（CoreMotion 原始值是向左为正），和屏幕坐标方向一致
    var pitch: Double   // 点头。低头为负、抬头为正
    var roll: Double    // 歪头
    var yawCalibrated = false
    var postureCalibrated = false
    var timestamp: TimeInterval

    static let zero = HeadPose(yaw: 0, pitch: 0, roll: 0, timestamp: 0)

    init(yaw: Double, pitch: Double, roll: Double, timestamp: TimeInterval, yawCalibrated: Bool = false, postureCalibrated: Bool = false) {
        self.yawCalibrated = yawCalibrated
        self.postureCalibrated = postureCalibrated
        self.yaw = yaw; self.pitch = pitch; self.roll = roll; self.timestamp = timestamp
    }

    init(attitude: CMAttitude, timestamp: TimeInterval) {
        self.init(yaw: -attitude.yaw.degrees, pitch: attitude.pitch.degrees, roll: attitude.roll.degrees, timestamp: timestamp)
    }

    mutating func applyReferenceValidity(hasReference: Bool, yawZero: Double?, rawYaw: Double) {
        // All calibrated axes share the same relative rotation; raw Euler yaw couples with nodding.
        if !hasReference { yaw = yawZero.map { wrappedDegrees(rawYaw - $0) } ?? 0 }
        yawCalibrated = yawZero != nil
        postureCalibrated = hasReference
    }
}

/// 数据来自哪只耳机。只戴一只时也能拿到数据，这里告诉你是哪只在提供。
enum SensorSide {
    case left, right, unknown

    init(_ location: CMDeviceMotion.SensorLocation) {
        switch location {
        case .headphoneLeft: self = .left
        case .headphoneRight: self = .right
        default: self = .unknown
        }
    }
}

extension Double {
    var degrees: Double { self * 180 / .pi }
}
