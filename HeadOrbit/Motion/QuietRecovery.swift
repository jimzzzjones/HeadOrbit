import Foundation

func wrappedDegrees(_ angle: Double) -> Double {
    let value = (angle + 180).truncatingRemainder(dividingBy: 360)
    return (value < 0 ? value + 360 : value) - 180
}

struct QuietRecovery {
    enum State: Equatable { case collecting, waitingForActivity, ready(Double) }
    enum Reason: String { case activity, warmingUp, moving, posture, stabilizing, conflict, expired, invalid, ready }

    struct Sample {
        var time: TimeInterval
        var yaw: Double
        var pitch: Double
        var roll: Double
        var rotationSpeed: Double
        var acceleration: Double
        var lastInteraction: TimeInterval?
    }

    private(set) var state: State = .waitingForActivity
    private(set) var reason: Reason = .activity
    private(set) var referenceTime: TimeInterval?
    var completedWindows: Int { centers.count }
    private var startedAt: TimeInterval?
    private var eligibleAt: TimeInterval?
    private var windowStart: TimeInterval?
    private var windowYaw: Double = 0
    private var deltas: [Double] = []
    private var windowSamples: [Sample] = []
    private var candidateSamples: [Sample] = []
    private var nextWindowAt: TimeInterval = 0
    private struct Center { var yaw: Double; var pitch: Double; var roll: Double }
    private var centers: [Center] = []
    private var lastTime: TimeInterval?

    mutating func update(_ sample: Sample) -> Double? {
        if case .ready = state { return nil }
        guard [sample.time, sample.yaw, sample.pitch, sample.roll,
               sample.rotationSpeed, sample.acceleration].allSatisfy(\.isFinite) else {
            wait(at: sample.time.isFinite ? sample.time : nil, reason: .invalid)
            return nil
        }
        if let lastTime, sample.time <= lastTime || sample.time - lastTime > 0.5 {
            wait(at: sample.time, reason: .invalid)
            return nil
        }
        lastTime = sample.time
        if state == .waitingForActivity {
            if let eligibleAt, sample.time >= eligibleAt { reason = .activity }
            guard let interaction = sample.lastInteraction, interaction.isFinite,
                  interaction <= sample.time, sample.time - interaction <= 1,
                  eligibleAt.map({ sample.time >= $0 && interaction >= $0 }) ?? true else { return nil }
            startedAt = sample.time
            state = .collecting
        }
        let age = sample.time - startedAt!
        // Activity opens a fixed observation period; repeated clicks cannot extend it.
        guard age < 15 else { wait(at: sample.time, reason: .expired); return nil }
        guard age >= 2 else { reason = .warmingUp; return nil }
        guard sample.rotationSpeed <= 35, sample.acceleration <= 0.15 else {
            clearWindow()
            reason = .moving
            return nil
        }
        guard abs(sample.pitch) <= 45, abs(sample.roll) <= 25 else {
            clearWindow()
            reason = .posture
            return nil
        }
        reason = .stabilizing
        guard sample.time >= nextWindowAt else { return nil }
        if windowStart == nil {
            windowStart = sample.time
            windowYaw = sample.yaw
        }
        let delta = wrappedDegrees(sample.yaw - windowYaw)
        guard abs(delta) <= 12 else { clearWindow(); reason = .moving; return nil }
        guard windowSamples.count < 1024 else { wait(at: sample.time, reason: .invalid); return nil }
        deltas.append(delta)
        windowSamples.append(sample)
        guard sample.time - windowStart! >= 1.5, deltas.count >= 15 else { return nil }
        let pitch = windowSamples.map(\.pitch)
        let roll = windowSamples.map(\.roll)
        // Small oscillations and brief measurement spikes should not demand perfect stillness.
        guard [deltas, pitch, roll].allSatisfy({ centralRange($0) <= 6 }) else {
            clearWindow(); reason = .moving; return nil
        }
        let center = Center(yaw: wrappedDegrees(windowYaw + trimmedMean(deltas)),
                            pitch: trimmedMean(pitch), roll: trimmedMean(roll))
        if let first = centers.first,
           abs(wrappedDegrees(center.yaw - first.yaw)) > 4 ||
           abs(center.pitch - first.pitch) > 5 || abs(center.roll - first.roll) > 5 {
            wait(at: sample.time, reason: .conflict)
            return nil
        }
        candidateSamples.append(contentsOf: windowSamples)
        centers.append(center)
        clearWindow()
        nextWindowAt = sample.time + 1
        guard centers.count == 3 else { return nil }
        guard abs(fittedYawChange()) <= 3 else {
            wait(at: sample.time, reason: .conflict)
            return nil
        }
        let first = centers[0].yaw
        let result = wrappedDegrees(first + centers.map { wrappedDegrees($0.yaw - first) }.reduce(0, +) / 3)
        let poseCenter = Center(yaw: result, pitch: centers.map(\.pitch).reduce(0, +) / 3,
                                roll: centers.map(\.roll).reduce(0, +) / 3)
        referenceTime = candidateSamples.min {
            distance($0, to: poseCenter) < distance($1, to: poseCenter)
        }?.time
        state = .ready(result)
        reason = .ready
        return result
    }

    private func fittedYawChange() -> Double {
        guard let first = candidateSamples.first, let last = candidateSamples.last else { return 0 }
        let times = candidateSamples.map { $0.time - first.time }
        let angles = candidateSamples.map { wrappedDegrees($0.yaw - first.yaw) }
        let meanTime = times.reduce(0, +) / Double(times.count)
        let meanAngle = angles.reduce(0, +) / Double(angles.count)
        let variance = times.reduce(0) { $0 + pow($1 - meanTime, 2) }
        guard variance > 0 else { return 0 }
        let covariance = zip(times, angles).reduce(0) { $0 + ($1.0 - meanTime) * ($1.1 - meanAngle) }
        return covariance / variance * (last.time - first.time)
    }

    private func centralRange(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let trim = sorted.count / 10
        return sorted[sorted.count - trim - 1] - sorted[trim]
    }

    private func trimmedMean(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let trim = sorted.count / 10
        let middle = sorted[trim..<(sorted.count - trim)]
        return middle.reduce(0, +) / Double(middle.count)
    }

    private func distance(_ sample: Sample, to center: Center) -> Double {
        pow(wrappedDegrees(sample.yaw - center.yaw), 2) +
            pow(sample.pitch - center.pitch, 2) + pow(sample.roll - center.roll, 2)
    }

    private mutating func wait(at time: TimeInterval?, reason: Reason) {
        self = QuietRecovery()
        self.reason = reason
        eligibleAt = time.map { $0 + 5 }
        lastTime = time
    }

    private mutating func clearWindow() {
        windowStart = nil
        deltas.removeAll(keepingCapacity: true)
        windowSamples.removeAll(keepingCapacity: true)
    }
}

struct MotionContinuity {
    static func sampleIsFresh(isTracking: Bool, lastArrival: TimeInterval?, now: TimeInterval) -> Bool {
        guard isTracking, let lastArrival else { return false }
        return now >= lastArrival && now - lastArrival <= 0.5
    }

    private var lastTimestamp: TimeInterval?
    private var lastArrival: TimeInterval?
    private var lastSide: Int?
    private var lastYaw: Double?
    private var lastPitch: Double?
    private var lastRoll: Double?

    mutating func accept(timestamp: TimeInterval, arrival: TimeInterval,
                         side: Int, yaw: Double, speed: Double, pitch: Double = 0, roll: Double = 0) -> Bool {
        defer {
            lastTimestamp = timestamp
            lastArrival = arrival
            lastSide = side
            lastYaw = yaw
            lastPitch = pitch
            lastRoll = roll
        }
        guard let previous = lastTimestamp, let arrived = lastArrival else { return true }
        if timestamp <= previous || timestamp - previous > 0.5 || arrival - arrived > 0.5 ||
            arrival < arrived || lastSide != side { return false }
        // A large jump with almost no angular velocity may be an unannounced reference reset.
        if speed < 8 {
            if let lastYaw, abs(wrappedDegrees(yaw - lastYaw)) > 35 { return false }
            if let lastPitch, abs(wrappedDegrees(pitch - lastPitch)) > 35 { return false }
            if let lastRoll, abs(wrappedDegrees(roll - lastRoll)) > 35 { return false }
        }
        return true
    }
}
