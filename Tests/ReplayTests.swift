import Foundation
import Combine
private var failures = 0
private func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line)") }
}
private func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(!value, file: file, line: line)
}
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected)") }
}
private func XCTAssertLessThan(_ actual: Double, _ limit: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(actual < limit, file: file, line: line)
}
private func XCTAssertNil<T>(_ actual: T?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(actual == nil, file: file, line: line)
}


final class RecoveryTests {
    private func run(_ r: inout QuietRecovery, from: Int = 0, until: Int = 150,
                     yaw: (Double) -> Double = { _ in 25 },
                     speed: (Double) -> Double = { _ in 0.3 },
                     interaction: (Double) -> Double? = { $0 }) -> [Double] {
        var result: [Double] = []
        for i in from...until {
            let t = Double(i) / 10
            if let value = r.update(.init(time: t, yaw: yaw(t), pitch: 10, roll: 3,
                                         rotationSpeed: speed(t), acceleration: 0.005,
                                         lastInteraction: interaction(t))) { result.append(value) }
        }
        return result
    }

    func testSingleClickThenReadingCompletesThreeWindows() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, until: 70, interaction: { $0 == 0 ? 0 : nil }).isEmpty)
        XCTAssertEqual(run(&r, from: 71, until: 150, interaction: { _ in nil }), [25])
        XCTAssertEqual(r.completedWindows, 3)
        XCTAssertEqual(r.state, .ready(25))
    }
    func testOpeningClickBeforeFirstFrameCanStartObservation() {
        var r = QuietRecovery()
        XCTAssertEqual(run(&r, from: 405, until: 540, interaction: { _ in 40 }), [25])
    }
    func testNoActivityForMinutesThenSingleActivityRecovers() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, until: 1800, interaction: { _ in nil }).isEmpty)
        XCTAssertEqual(r.reason, .activity)
        XCTAssertEqual(run(&r, from: 1801, until: 1930, interaction: { $0 == 180.1 ? $0 : nil }), [25])
    }
    func testOldFutureAndNonfiniteActivityCannotStart() {
        for offset in [-2.0, 1.0, Double.nan] {
            var r = QuietRecovery()
            XCTAssertTrue(run(&r, interaction: { $0 + offset }).isEmpty)
            XCTAssertEqual(r.state, .waitingForActivity)
        }
    }
    func testRepeatedActivityDoesNotExtendObservation() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, until: 149, speed: { _ in 60 }).isEmpty)
        XCTAssertEqual(r.state, .collecting)
        XCTAssertTrue(run(&r, from: 150, until: 199, speed: { _ in 60 }).isEmpty)
        XCTAssertEqual(r.state, .waitingForActivity)
        XCTAssertEqual(r.reason, .expired)
        XCTAssertEqual(r.completedWindows, 0)
    }
    func testCooldownActivityCannotBeReused() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, until: 150, speed: { _ in 60 }).isEmpty)
        XCTAssertTrue(run(&r, from: 151, until: 210, interaction: { _ in 19.9 }).isEmpty)
        XCTAssertEqual(r.state, .waitingForActivity)
        XCTAssertEqual(r.reason, .activity)
        XCTAssertTrue(run(&r, from: 211, until: 230, interaction: { _ in 21.1 }).isEmpty)
        XCTAssertEqual(r.state, .collecting)
        XCTAssertEqual(run(&r, from: 231, until: 350, interaction: { _ in nil }), [25])
    }
    func testExpiredCandidateClearedBeforeNextAttempt() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, until: 150, speed: { $0 < 4 ? 0 : 60 }).isEmpty)
        XCTAssertEqual(r.completedWindows, 0)
        XCTAssertTrue(run(&r, from: 151, until: 199, interaction: { _ in 0 }).isEmpty)
        XCTAssertEqual(run(&r, from: 200, until: 340, yaw: { _ in -15 }, interaction: { $0 == 20 ? 20 : nil }), [-15])
    }
    func testConflictingDirectionsWaitThenStartFresh() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, until: 100, yaw: { $0 < 4 ? 0 : 25 }).isEmpty)
        XCTAssertEqual(r.state, .waitingForActivity)
        XCTAssertEqual(r.reason, .conflict)
        XCTAssertEqual(r.completedWindows, 0)
        XCTAssertEqual(run(&r, from: 101, until: 260, yaw: { _ in -15 }), [-15])
    }
    func testMultipleFailuresStillAllowLaterSuccess() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, until: 150, speed: { _ in 60 }).isEmpty)
        XCTAssertTrue(run(&r, from: 151, until: 350, speed: { _ in 60 }).isEmpty)
        XCTAssertEqual(r.state, .waitingForActivity)
        XCTAssertEqual(run(&r, from: 351, until: 540), [25])
    }
    func testBlockingReasonsDoNotClaimPostureErrorForMotion() {
        for (speed, accel, pitch, roll, reason) in [
            (60.0, 0.0, 0.0, 0.0, QuietRecovery.Reason.moving),
            (0.0, 0.3, 0.0, 0.0, .moving),
            (0.0, 0.0, 50.0, 0.0, .posture),
            (0.0, 0.0, 0.0, 30.0, .posture)
        ] {
            var r = QuietRecovery()
            for i in 0...30 {
                let t = Double(i)/10
                XCTAssertNil(r.update(.init(time: t, yaw: 0, pitch: pitch, roll: roll,
                                           rotationSpeed: speed, acceleration: accel, lastInteraction: t)))
            }
            XCTAssertEqual(r.reason, reason)
        }
    }
    func testCircularMeanAcrossWrap() {
        var r = QuietRecovery()
        let centers = run(&r, yaw: { Int($0 * 10) % 2 == 0 ? 179.5 : -179.5 })
        XCTAssertEqual(centers.count, 1)
        if let center = centers.first { XCTAssertLessThan(abs(wrappedDegrees(center - 180)), 0.1) }
        XCTAssertEqual(wrappedDegrees(-179 - 179), 2)
    }
    func testLockedCenterNeverLearnsSlowTurn() {
        var r = QuietRecovery()
        XCTAssertEqual(run(&r), [25])
        XCTAssertTrue(run(&r, from: 151, until: 900, yaw: { $0 }, speed: { _ in 0.5 }).isEmpty)
        XCTAssertEqual(r.state, .ready(25))
    }
    func testNonFiniteSampleWaitsThenRecovers() {
        var r = QuietRecovery()
        XCTAssertNil(r.update(.init(time: 0, yaw: .nan, pitch: 0, roll: 0,
                                   rotationSpeed: 0, acceleration: 0, lastInteraction: nil)))
        XCTAssertEqual(r.reason, .invalid)
        XCTAssertEqual(run(&r, from: 1, until: 180), [25])
    }
    func testSampleGapAndClockRollbackClearCandidates() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, until: 60).isEmpty)
        XCTAssertNil(r.update(.init(time: 10, yaw: 25, pitch: 10, roll: 3,
                                   rotationSpeed: 0, acceleration: 0, lastInteraction: 10)))
        XCTAssertEqual(r.state, .waitingForActivity)
        XCTAssertEqual(r.completedWindows, 0)
        XCTAssertTrue(run(&r, from: 101, until: 149).isEmpty)
        XCTAssertNil(r.update(.init(time: 5, yaw: 25, pitch: 10, roll: 3,
                                   rotationSpeed: 0, acceleration: 0, lastInteraction: 5)))
        XCTAssertTrue(run(&r, from: 51, until: 120, interaction: { _ in 9.9 }).isEmpty)
        XCTAssertEqual(run(&r, from: 121, until: 250), [25])
    }
    func testContinuedSideLookingIsNotDistinguishableFromForward() {
        var r = QuietRecovery()
        XCTAssertEqual(run(&r, yaw: { _ in 70 }), [70])
    }
    func testModerateSlowTurnDoesNotQualify() {
        var r = QuietRecovery()
        XCTAssertTrue(run(&r, yaw: { $0 * 2 }, speed: { _ in 2 }).isEmpty)
    }

    func testNaturalSmallMovementsAcrossPhasesAndSpeeds() {
        for amplitude in [1.0, 2.0, 3.0] {
            for frequency in [0.35, 0.5, 0.8, 1.2] {
                for phase in [0.0, Double.pi / 2, Double.pi, Double.pi * 1.5] {
                    var r = QuietRecovery()
                    var result: Double?
                    for i in 0...749 {
                        let t = Double(i) / 50
                        let angle = 2 * Double.pi * frequency * t + phase
                        let yawRate = amplitude * 2 * Double.pi * frequency * cos(angle)
                        result = r.update(.init(time: t, yaw: amplitude * sin(angle),
                                                pitch: 10 + 2 * sin(angle * 0.7), roll: 1.5 * cos(angle * 0.6),
                                                rotationSpeed: sqrt(yawRate * yawRate + 25),
                                                acceleration: 0.06, lastInteraction: i == 0 ? 0 : nil)) ?? result
                    }
                    XCTAssertTrue(result != nil)
                    if let result { XCTAssertLessThan(abs(result), 2) }
                    XCTAssertTrue(r.referenceTime != nil)
                }
            }
        }
    }

    func testBriefVelocityAndAccelerationPeaksDoNotDemandStillness() {
        var r = QuietRecovery()
        var result: Double?
        for i in 0...749 {
            let t = Double(i) / 50
            result = r.update(.init(time: t, yaw: sin(t * 3), pitch: 10, roll: 0,
                                    rotationSpeed: i % 30 == 0 ? 25 : 2,
                                    acceleration: i % 30 == 0 ? 0.1 : 0.01,
                                    lastInteraction: i == 0 ? 0 : nil)) ?? result
        }
        XCTAssertTrue(result != nil)
    }

    func testContinuousDriftWithSmallOscillationDoesNotQualify() {
        for speed in [0.5, 1.0, 2.0] {
            var r = QuietRecovery()
            XCTAssertTrue(run(&r, yaw: { speed * $0 + 0.2 * sin($0 * 4) }, speed: { _ in 3 }).isEmpty)
            XCTAssertNil(r.referenceTime)
        }
    }

    func testRepresentativeReferenceComesFromCenterNotCompletionPeak() {
        var r = QuietRecovery()
        var samples: [QuietRecovery.Sample] = []
        for i in 0...749 {
            let t = Double(i) / 50
            let s = QuietRecovery.Sample(time: t, yaw: 2 * sin(t * .pi),
                                        pitch: 10 + 2 * sin(t * .pi), roll: 0,
                                        rotationSpeed: 8, acceleration: 0.05,
                                        lastInteraction: i == 0 ? 0 : nil)
            samples.append(s)
            if r.update(s) != nil { break }
        }
        guard let time = r.referenceTime, let reference = samples.first(where: { $0.time == time }) else {
            XCTAssertTrue(false); return
        }
        XCTAssertTrue(time <= samples.last!.time)
        XCTAssertLessThan(abs(reference.yaw), 0.5)
        XCTAssertLessThan(abs(reference.pitch - 10), 0.5)
        XCTAssertTrue(abs(samples.last!.pitch - 10) > 1)
        XCTAssertEqual(r.completedWindows, 3)
    }

    func testAbnormallyDenseSamplesCannotGrowWindowWithoutBound() {
        var r = QuietRecovery()
        _ = run(&r, until: 20)
        for i in 1...1100 {
            XCTAssertNil(r.update(.init(time: 2 + Double(i) / 10000, yaw: 25, pitch: 10, roll: 3,
                                       rotationSpeed: 0, acceleration: 0, lastInteraction: nil)))
        }
        XCTAssertEqual(r.state, .waitingForActivity)
        XCTAssertEqual(r.reason, .invalid)
        XCTAssertNil(r.referenceTime)
        XCTAssertEqual(r.completedWindows, 0)
    }
}

final class ContinuityTests {
    private func seeded() -> MotionContinuity {
        var c = MotionContinuity()
        XCTAssertTrue(c.accept(timestamp: 10, arrival: 100, side: 1, yaw: 0, speed: 0))
        return c
    }
    func testNormalStreamAndAngleWrap() {
        var c = MotionContinuity()
        XCTAssertTrue(c.accept(timestamp: 10, arrival: 100, side: 1, yaw: 179, speed: 0))
        XCTAssertTrue(c.accept(timestamp: 10.1, arrival: 100.1, side: 1, yaw: -179, speed: 0))
    }
    func testSideSwitchInvalidates() {
        var c = seeded()
        XCTAssertFalse(c.accept(timestamp: 10.1, arrival: 100.1, side: 2, yaw: 0, speed: 0))
    }
    func testSensorClockRollbackInvalidates() {
        var c = seeded()
        XCTAssertFalse(c.accept(timestamp: 1, arrival: 100.1, side: 1, yaw: 0, speed: 0))
    }
    func testMotionOrDeliveryGapInvalidates() {
        var c = seeded()
        XCTAssertFalse(c.accept(timestamp: 11, arrival: 101, side: 1, yaw: 0, speed: 0))
        c = seeded()
        XCTAssertFalse(c.accept(timestamp: 10.1, arrival: 103, side: 1, yaw: 0, speed: 0))
    }
    func testUnannouncedReferenceJumpsInAllAxesInvalidate() {
        var c = seeded()
        XCTAssertFalse(c.accept(timestamp: 10.1, arrival: 100.1, side: 1, yaw: 80, speed: 0))
        c = seeded()
        XCTAssertFalse(c.accept(timestamp: 10.1, arrival: 100.1, side: 1, yaw: 0, speed: 0, pitch: 50))
        c = seeded()
        XCTAssertFalse(c.accept(timestamp: 10.1, arrival: 100.1, side: 1, yaw: 0, speed: 0, roll: 50))
    }
    func testRealFastTurnDoesNotMasqueradeAsReset() {
        var c = seeded()
        XCTAssertTrue(c.accept(timestamp: 10.1, arrival: 100.1, side: 1, yaw: 45, speed: 450))
    }
}

final class ActionGateTests {
    func testRelativePitchDoesNotAcquireRawEulerYaw() {
        var pose = HeadPose(yaw: 0, pitch: 20, roll: 0, timestamp: 1)
        pose.applyReferenceValidity(hasReference: true, yawZero: 45, rawYaw: 61.91)
        XCTAssertEqual(pose.yaw, 0)
        XCTAssertEqual(pose.pitch, 20)
        XCTAssertTrue(pose.postureCalibrated)
        var raw = HeadPose(yaw: 61.91, pitch: 20, roll: 0, timestamp: 2)
        raw.applyReferenceValidity(hasReference: false, yawZero: nil, rawYaw: 61.91)
        XCTAssertFalse(raw.postureCalibrated)
        XCTAssertEqual(raw.pitch, 20)
    }
    final class PostureDwellProbe: HeadAction {
        let id = "posture-probe"
        let title = "Posture probe"
        var isEnabled = true
        let needsPostureCalibration = true
        var trigger = DwellTrigger(threshold: 15, enterDwell: 2, hysteresis: 5, exitDwell: 0.8)
        func process(_ pose: HeadPose) { _ = trigger.update(pose.pitch, at: pose.timestamp) }
        func reset() { trigger.reset() }
    }

    func testPostureEntersExitsAndResetsAfterReferenceIsValid() {
        let samples = PassthroughSubject<HeadPose, Never>()
        let tracking = PassthroughSubject<Bool, Never>()
        let resets = PassthroughSubject<Void, Never>()
        let posture = PostureDwellProbe()
        let engine = ActionEngine(samples: samples.eraseToAnyPublisher(), tracking: tracking.eraseToAnyPublisher(),
                                  resets: resets.eraseToAnyPublisher(), actions: [posture])
        for t in [0.0, 1, 2.1] {
            samples.send(.init(yaw: 0, pitch: 20, roll: 0, timestamp: t, yawCalibrated: true, postureCalibrated: true))
        }
        XCTAssertTrue(posture.trigger.isActive)
        for t in [3.0, 3.9] {
            samples.send(.init(yaw: 0, pitch: 0, roll: 0, timestamp: t, yawCalibrated: true, postureCalibrated: true))
        }
        XCTAssertFalse(posture.trigger.isActive)
        for t in [4.0, 5, 6.1] {
            samples.send(.init(yaw: 0, pitch: 20, roll: 0, timestamp: t, yawCalibrated: true, postureCalibrated: true))
        }
        XCTAssertTrue(posture.trigger.isActive)
        tracking.send(false)
        XCTAssertFalse(posture.trigger.isActive)
        for t in [7.0, 8, 9.1] { samples.send(.init(yaw: 0, pitch: 20, roll: 0, timestamp: t)) }
        XCTAssertFalse(posture.trigger.isActive)
        withExtendedLifetime(engine) {}
    }
    final class SpyAction: HeadAction {
        let id = UUID().uuidString
        let title = "Spy"
        var isEnabled = true
        let needsPostureCalibration: Bool
        var count = 0
        var resets = 0
        init(posture: Bool) { needsPostureCalibration = posture }
        func process(_ pose: HeadPose) { count += 1 }
        func reset() { resets += 1 }
    }

    func testUncalibratedPitchIsGatedAndCalibratedPitchIsDelivered() {
        let samples = PassthroughSubject<HeadPose, Never>()
        let tracking = PassthroughSubject<Bool, Never>()
        let resets = PassthroughSubject<Void, Never>()
        let yaw = SpyAction(posture: false)
        let pitch = SpyAction(posture: true)
        let engine = ActionEngine(samples: samples.eraseToAnyPublisher(), tracking: tracking.eraseToAnyPublisher(),
                                  resets: resets.eraseToAnyPublisher(), actions: [yaw, pitch])
        samples.send(.init(yaw: 40, pitch: 40, roll: 0, timestamp: 1))
        XCTAssertEqual(yaw.count, 0)
        XCTAssertEqual(pitch.count, 0)
        samples.send(.init(yaw: 40, pitch: 40, roll: 0, timestamp: 2, yawCalibrated: true))
        XCTAssertEqual(yaw.count, 1)
        XCTAssertEqual(pitch.count, 0)
        samples.send(.init(yaw: 40, pitch: 40, roll: 0, timestamp: 3,
                                   yawCalibrated: true, postureCalibrated: true))
        XCTAssertEqual(yaw.count, 2)
        XCTAssertEqual(pitch.count, 1)
        let resetCount = yaw.resets
        resets.send()
        XCTAssertEqual(yaw.resets, resetCount + 1)
        withExtendedLifetime(engine) {}
    }

    func testManualCalibrationWithoutFreshSampleIsNoOp() {
        XCTAssertFalse(MotionContinuity.sampleIsFresh(isTracking: false, lastArrival: 10, now: 10.1))
        XCTAssertFalse(MotionContinuity.sampleIsFresh(isTracking: true, lastArrival: nil, now: 10))
        XCTAssertFalse(MotionContinuity.sampleIsFresh(isTracking: true, lastArrival: 10, now: 11))
        XCTAssertTrue(MotionContinuity.sampleIsFresh(isTracking: true, lastArrival: 10, now: 10.1))
    }
}

final class ReconnectTests {
    private func exhaustedSchedule() -> ReconnectSchedule {
        var r = ReconnectSchedule()
        r.request(at: 0)
        for time in [1.0, 13.0, 38.0] { XCTAssertTrue(r.takeDueAttempt(at: time)) }
        return r
    }

    func testBluetoothInputReturnWithUnchangedDeviceList() {
        let before = AudioRouteSnapshot(bluetoothDevices: [10], defaultInput: 1, defaultOutput: 10)
        let after = AudioRouteSnapshot(bluetoothDevices: [10], defaultInput: 10, defaultOutput: 10)
        var r = exhaustedSchedule()
        r.routeChanged(from: before, to: after, at: 100)
        XCTAssertFalse(r.exhausted)
        XCTAssertFalse(r.takeDueAttempt(at: 100.9))
        XCTAssertTrue(r.takeDueAttempt(at: 101))
        r.routeChanged(from: after, to: after, at: 102)
        XCTAssertTrue(r.takeDueAttempt(at: 113))
        XCTAssertTrue(r.takeDueAttempt(at: 138))
        XCTAssertFalse(r.takeDueAttempt(at: 1000))
        XCTAssertTrue(r.exhausted)
    }

    func testBluetoothOutputAndDeviceReturn() {
        let snapshots = [
            AudioRouteSnapshot(bluetoothDevices: [], defaultInput: 1, defaultOutput: 1),
            AudioRouteSnapshot(bluetoothDevices: [10, 20], defaultInput: 1, defaultOutput: 1),
            AudioRouteSnapshot(bluetoothDevices: [10, 20], defaultInput: 1, defaultOutput: 10)
        ]
        let after = AudioRouteSnapshot(bluetoothDevices: [10, 20], defaultInput: 1, defaultOutput: 20)
        for before in snapshots {
            var r = exhaustedSchedule()
            r.routeChanged(from: before, to: after, at: 100)
            XCTAssertTrue(r.takeDueAttempt(at: 101))
            r.receivedSample()
            XCTAssertFalse(r.takeDueAttempt(at: 500))
        }
    }

    func testBluetoothClassificationArrivesAfterDefaultDevice() {
        let before = AudioRouteSnapshot(bluetoothDevices: [10], defaultInput: 20, defaultOutput: 20)
        let after = AudioRouteSnapshot(bluetoothDevices: [10, 20], defaultInput: 20, defaultOutput: 20)
        var r = exhaustedSchedule()
        r.routeChanged(from: before, to: after, at: 100)
        XCTAssertTrue(r.takeDueAttempt(at: 101))
        r.routeChanged(from: after, to: after, at: 105)
        XCTAssertEqual(r.attempts, 1)
    }

    func testUnrelatedAndUnknownRoutesDoNotRefillBudget() {
        let before = AudioRouteSnapshot(bluetoothDevices: [10], defaultInput: 1, defaultOutput: 1)
        let unrelated = AudioRouteSnapshot(bluetoothDevices: [10], defaultInput: 2, defaultOutput: 2)
        let unknown = AudioRouteSnapshot(isKnown: false, bluetoothDevices: [10], defaultInput: 10, defaultOutput: 10)
        for (old, new) in [(Optional(before), before), (Optional(before), unrelated),
                           (Optional(before), unknown), (Optional(unknown), before), (nil, before)] {
            var r = exhaustedSchedule()
            r.routeChanged(from: old, to: new, at: 100)
            XCTAssertTrue(r.exhausted)
            XCTAssertFalse(r.takeDueAttempt(at: 1000))
        }
        var initial = ReconnectSchedule()
        initial.routeChanged(from: nil, to: before, at: 100)
        XCTAssertFalse(initial.takeDueAttempt(at: 111))
        XCTAssertTrue(initial.takeDueAttempt(at: 112))
    }

    func testRetryBudgetAndGracePeriods() {
        var r = ReconnectSchedule()
        r.request(at: 100)
        XCTAssertFalse(r.takeDueAttempt(at: 100.9))
        XCTAssertTrue(r.takeDueAttempt(at: 101))
        r.request(at: 102)
        XCTAssertFalse(r.takeDueAttempt(at: 112))
        XCTAssertTrue(r.takeDueAttempt(at: 113))
        XCTAssertFalse(r.takeDueAttempt(at: 137))
        XCTAssertTrue(r.takeDueAttempt(at: 138))
        XCTAssertTrue(r.exhausted)
        r.request(at: 500)
        XCTAssertFalse(r.takeDueAttempt(at: 1000))
    }
    func testFirstValidSampleCancelsPendingRetry() {
        var r = ReconnectSchedule()
        r.request(at: 10)
        r.receivedSample()
        XCTAssertFalse(r.takeDueAttempt(at: 100))
        XCTAssertEqual(r.attempts, 0)
        r.request(at: 101)
        XCTAssertTrue(r.takeDueAttempt(at: 102))
    }
    func testRepeatedConnectCallbacksCannotPostponeRecovery() {
        var r = ReconnectSchedule()
        r.request(at: 10)
        r.request(at: 10.5)
        XCTAssertTrue(r.takeDueAttempt(at: 11))
    }
}

final class DiagnosticTests {
    func testBoundedBufferAndCSVColumns() {
        let d = MotionDiagnostics()
        for i in 0...3000 {
            d.record(.init(time: Double(i)/10, sensorTime: Double(i)/10, epoch: 2,
                           rawYaw: 5, yaw: -3, rawPitch: 2, rawRoll: 0,
                           rotationX: 0, rotationY: 0, rotationZ: 0, acceleration: 0,
                           side: 1, yawValid: true, postureValid: false, mode: "automatic"))
        }
        XCTAssertTrue(d.rows.count <= 1201)
        XCTAssertTrue(d.rows.first!.time >= 180)
        let lines = d.csv().split(separator: "\n")
        XCTAssertTrue(lines.allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == 20 })
        XCTAssertTrue(lines[0].contains("raw_yaw_deg"))
    }
}

@main
struct ReplayRunner {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("testAbnormallyDenseSamplesCannotGrowWindowWithoutBound", RecoveryTests().testAbnormallyDenseSamplesCannotGrowWindowWithoutBound),
            ("testRelativePitchDoesNotAcquireRawEulerYaw", ActionGateTests().testRelativePitchDoesNotAcquireRawEulerYaw),
            ("testNaturalSmallMovementsAcrossPhasesAndSpeeds", RecoveryTests().testNaturalSmallMovementsAcrossPhasesAndSpeeds),
            ("testBriefVelocityAndAccelerationPeaksDoNotDemandStillness", RecoveryTests().testBriefVelocityAndAccelerationPeaksDoNotDemandStillness),
            ("testContinuousDriftWithSmallOscillationDoesNotQualify", RecoveryTests().testContinuousDriftWithSmallOscillationDoesNotQualify),
            ("testRepresentativeReferenceComesFromCenterNotCompletionPeak", RecoveryTests().testRepresentativeReferenceComesFromCenterNotCompletionPeak),
            ("testPostureEntersExitsAndResetsAfterReferenceIsValid", ActionGateTests().testPostureEntersExitsAndResetsAfterReferenceIsValid),
            ("testSingleClickThenReadingCompletesThreeWindows", RecoveryTests().testSingleClickThenReadingCompletesThreeWindows),
            ("testOpeningClickBeforeFirstFrameCanStartObservation", RecoveryTests().testOpeningClickBeforeFirstFrameCanStartObservation),
            ("testNoActivityForMinutesThenSingleActivityRecovers", RecoveryTests().testNoActivityForMinutesThenSingleActivityRecovers),
            ("testOldFutureAndNonfiniteActivityCannotStart", RecoveryTests().testOldFutureAndNonfiniteActivityCannotStart),
            ("testRepeatedActivityDoesNotExtendObservation", RecoveryTests().testRepeatedActivityDoesNotExtendObservation),
            ("testCooldownActivityCannotBeReused", RecoveryTests().testCooldownActivityCannotBeReused),
            ("testExpiredCandidateClearedBeforeNextAttempt", RecoveryTests().testExpiredCandidateClearedBeforeNextAttempt),
            ("testConflictingDirectionsWaitThenStartFresh", RecoveryTests().testConflictingDirectionsWaitThenStartFresh),
            ("testMultipleFailuresStillAllowLaterSuccess", RecoveryTests().testMultipleFailuresStillAllowLaterSuccess),
            ("testBlockingReasonsDoNotClaimPostureErrorForMotion", RecoveryTests().testBlockingReasonsDoNotClaimPostureErrorForMotion),
            ("testCircularMeanAcrossWrap", RecoveryTests().testCircularMeanAcrossWrap),
            ("testLockedCenterNeverLearnsSlowTurn", RecoveryTests().testLockedCenterNeverLearnsSlowTurn),
            ("testNonFiniteSampleWaitsThenRecovers", RecoveryTests().testNonFiniteSampleWaitsThenRecovers),
            ("testSampleGapAndClockRollbackClearCandidates", RecoveryTests().testSampleGapAndClockRollbackClearCandidates),
            ("testContinuedSideLookingIsNotDistinguishableFromForward", RecoveryTests().testContinuedSideLookingIsNotDistinguishableFromForward),
            ("testModerateSlowTurnDoesNotQualify", RecoveryTests().testModerateSlowTurnDoesNotQualify),
            ("testBluetoothInputReturnWithUnchangedDeviceList", ReconnectTests().testBluetoothInputReturnWithUnchangedDeviceList),
            ("testBluetoothOutputAndDeviceReturn", ReconnectTests().testBluetoothOutputAndDeviceReturn),
            ("testBluetoothClassificationArrivesAfterDefaultDevice", ReconnectTests().testBluetoothClassificationArrivesAfterDefaultDevice),
            ("testUnrelatedAndUnknownRoutesDoNotRefillBudget", ReconnectTests().testUnrelatedAndUnknownRoutesDoNotRefillBudget),
            ("testRetryBudgetAndGracePeriods", ReconnectTests().testRetryBudgetAndGracePeriods),
            ("testFirstValidSampleCancelsPendingRetry", ReconnectTests().testFirstValidSampleCancelsPendingRetry),
            ("testRepeatedConnectCallbacksCannotPostponeRecovery", ReconnectTests().testRepeatedConnectCallbacksCannotPostponeRecovery),
            ("testBoundedBufferAndCSVColumns", DiagnosticTests().testBoundedBufferAndCSVColumns),
            ("testNormalStreamAndAngleWrap", ContinuityTests().testNormalStreamAndAngleWrap),
            ("testSideSwitchInvalidates", ContinuityTests().testSideSwitchInvalidates),
            ("testSensorClockRollbackInvalidates", ContinuityTests().testSensorClockRollbackInvalidates),
            ("testMotionOrDeliveryGapInvalidates", ContinuityTests().testMotionOrDeliveryGapInvalidates),
            ("testUnannouncedReferenceJumpsInAllAxesInvalidate", ContinuityTests().testUnannouncedReferenceJumpsInAllAxesInvalidate),
            ("testRealFastTurnDoesNotMasqueradeAsReset", ContinuityTests().testRealFastTurnDoesNotMasqueradeAsReset),
            ("testUncalibratedPitchIsGatedAndCalibratedPitchIsDelivered", ActionGateTests().testUncalibratedPitchIsGatedAndCalibratedPitchIsDelivered),
            ("testManualCalibrationWithoutFreshSampleIsNoOp", ActionGateTests().testManualCalibrationWithoutFreshSampleIsNoOp),
        ]
        for (name, run) in cases {
            let before = failures
            run()
            print("\(failures == before ? "PASS" : "FAIL") \(name)")
        }
        print("\(cases.count) scenarios, \(failures) failed assertions")
        exit(failures == 0 ? 0 : 1)
    }
}
