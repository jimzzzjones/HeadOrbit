import AppKit
import Combine
import CoreMotion
import Foundation
import os

private let log = Logger(subsystem: "com.cogria.HeadOrbit", category: "HeadTracker")

/// 封装 CMHeadphoneMotionManager：
/// - 判断系统 / 权限 / 是否有支持头部追踪的 AirPods 在提供数据
/// - 输出相对校准基准的 HeadPose（校准 = 把当前姿态当作「正对屏幕」）
final class HeadTracker: NSObject, ObservableObject {
    enum Status: Equatable {
        case unsupported            // 系统不支持（理论上 macOS 14+ 都支持）
        case denied                 // 「运动与健身」权限被拒
        case restricted
        case waitingForPermission   // 还没询问 / 用户还没答
        case waitingForHeadphones   // 权限 OK，但没有支持头部追踪的耳机在送数据
        case tracking(SensorSide)   // 正常收数

        var isTracking: Bool { if case .tracking = self { return true } else { return false } }
    }

    @Published private(set) var status: Status = .waitingForPermission
    @Published private(set) var authorization: CMAuthorizationStatus = CMHeadphoneMotionManager.authorizationStatus()
    @Published private(set) var pose: HeadPose = .zero
    enum CalibrationState: Equatable { case recovering, waitingForActivity, needsForward, automatic, manual }
    @Published private(set) var isCalibrated = false
    @Published private(set) var isPostureCalibrated = false
    @Published private(set) var motionDataFresh = false
    @Published private(set) var calibrationState: CalibrationState = .recovering
    @Published private(set) var recoveryReason: QuietRecovery.Reason = .activity
    @Published private(set) var recenterShortcutAvailable = false
    @Published var quietRecoveryEnabled = UserDefaults.standard.object(forKey: "recovery.enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(quietRecoveryEnabled, forKey: "recovery.enabled")
            if !isCalibrated {
                recovery = QuietRecovery()
                recoveryReason = .activity
                calibrationState = quietRecoveryEnabled ? .waitingForActivity : .needsForward
            }
        }
    }
    @Published private(set) var lastError: String?
    /// 手动重连后的冷却：期间按钮禁用并显示「连接中」，避免连点把正在建立的会话拆掉
    @Published private(set) var isReconnecting = false
    @Published private(set) var headphonesRoutedAway = false
    @Published private(set) var bluetoothAudioPresent = false
    @Published private(set) var reconnectExhausted = false
    private var routeMonitor: AudioRouteMonitor?
    private var routeSnapshot: AudioRouteSnapshot?
    private var reconnectSchedule = ReconnectSchedule()

    /// 每一帧都会推送（比 @Published pose 更适合做逻辑，不受 SwiftUI 合并影响）
    let samples = PassthroughSubject<HeadPose, Never>()
    /// 用户点了校准。所有功能应据此清掉计时器、提醒和暂停，从当前姿态重新开始算
    let didRecenter = PassthroughSubject<Void, Never>()

    private var manager = CMHeadphoneMotionManager()
    let diagnostics = MotionDiagnostics()
    private var calibrationEpoch = 0
    let didInvalidateCalibration = PassthroughSubject<Void, Never>()
    let didPauseMotion = PassthroughSubject<Void, Never>()
    private var delivery = MotionDelivery()
    private var reference: CMAttitude?
    private var recoveryAttitudes: [(time: TimeInterval, attitude: CMAttitude)] = []
    private var yawZero: Double?
    private var recovery = QuietRecovery()
    private var recoveryReasonUpdatedAt: TimeInterval = -.infinity
    private var continuity = MotionContinuity()
    private var sessionGeneration = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var suspensionReasons = Set<String>()
    private lazy var recenterKey = GlobalHotKey(keyCode: GlobalHotKey.recenter,
                                               modifiers: GlobalHotKey.recenterModifiers) { [weak self] in
        self?.recenter()
    }
    private var lastAttitude: CMAttitude?
    private var staleTimer: Timer?
    private var permissionTimer: Timer?
    private var connectedByDelegate = false
    private var manualReconnectUntil: TimeInterval = 0
    private var lastRebuildAt: TimeInterval = -.infinity


    override init() {
        super.init()
        calibrationState = quietRecoveryEnabled ? .waitingForActivity : .needsForward
        manager.delegate = self
        refreshStatus()
        observeWorkspace()
        routeMonitor = AudioRouteMonitor { [weak self] in self?.refreshAudioRoute() }
    }

    deinit {
        staleTimer?.invalidate()
        permissionTimer?.invalidate()
        manager.delegate = nil
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        recenterKey.unregister()
    }

    var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }


    func start() {
        log.notice("start: available=\(self.manager.isDeviceMotionAvailable) active=\(self.manager.isDeviceMotionActive) auth=\(CMHeadphoneMotionManager.authorizationStatus().rawValue) connectionStatusActive=\(self.manager.isConnectionStatusActive)")
        guard suspensionReasons.isEmpty else { return }
        recenterKey.register()
        recenterShortcutAvailable = recenterKey.isRegistered
        guard manager.isDeviceMotionAvailable else { status = .unsupported; return }
        guard !manager.isDeviceMotionActive else { return }
        lastError = nil
        manager.startConnectionStatusUpdates()
        let generation = sessionGeneration
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, generation == self.sessionGeneration, self.suspensionReasons.isEmpty else { return }
            if let error {
                log.error("deviceMotion error: \(error.localizedDescription, privacy: .public) \((error as NSError).domain, privacy: .public)/\((error as NSError).code)")
                self.invalidateCalibration()
                self.status = .waitingForHeadphones
                self.reconnectSchedule.request(at: ProcessInfo.processInfo.systemUptime, delay: 3)
                self.lastError = error.localizedDescription
                self.refreshStatus()
                return
            }
            guard let motion else { return }
            if self.delivery.lastTimestamp == nil {
                log.notice("first sample: sensor=\(motion.sensorLocation.rawValue)")
                self.isReconnecting = false
            }
            self.handle(motion)
        }
        log.notice("startDeviceMotionUpdates called, active=\(self.manager.isDeviceMotionActive)")
        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkStale()
        }
        refreshStatus()
        refreshAudioRoute()
        if bluetoothAudioPresent || connectedByDelegate {
            reconnectSchedule.request(at: ProcessInfo.processInfo.systemUptime, delay: 12)
        }
        // 首次启动会弹「运动与健身」授权框。系统不会回调告诉我们用户点了什么，
        // 所以在未决期间轮询；一旦授权，重启采集，保证会话是在授权之后建立的。
        if authorization == .notDetermined { startPermissionPolling() }
    }

    /// 打开面板时调一下，把权限 / 状态刷成最新
    func refresh() {
        refreshStatus()
    }

    /// 用户手动点「重新连接」：销毁当前采集会话，换一个全新的 CMHeadphoneMotionManager 重来。
    /// 用于「先开程序后戴耳机」或系统那边的传感器流卡住没数据的情况。
    func reconnect() {
        guard !isReconnecting, suspensionReasons.isEmpty else { return }
        manualReconnectUntil = ProcessInfo.processInfo.systemUptime + 5
        isReconnecting = true
        reconnectSchedule = ReconnectSchedule()
        reconnectSchedule.request(at: ProcessInfo.processInfo.systemUptime, delay: 12)
        rebuildSession()
    }

    private func rebuildSession() {
        sessionGeneration += 1
        invalidateCalibration()
        lastRebuildAt = ProcessInfo.processInfo.systemUptime
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        manager.delegate = nil
        manager = CMHeadphoneMotionManager()
        manager.delegate = self
        status = .waitingForHeadphones
        start()
    }

    func stop() {
        log.notice("stop")
        sessionGeneration += 1
        reconnectSchedule = ReconnectSchedule()
        invalidateCalibration()
        recenterKey.unregister()
        recenterShortcutAvailable = false
        status = .waitingForHeadphones
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        staleTimer?.invalidate(); staleTimer = nil
        permissionTimer?.invalidate(); permissionTimer = nil
        refreshStatus()
    }

    func recenter() {
        guard freshSample, let att = lastAttitude?.copy() as? CMAttitude else { return }
        reference = att
        recoveryAttitudes.removeAll(keepingCapacity: true)
        isPostureCalibrated = true
        recenterYaw()
        pose = HeadPose(yaw: 0, pitch: 0, roll: 0, timestamp: pose.timestamp,
                        yawCalibrated: true, postureCalibrated: true)
    }

    func recenterYaw() {
        guard freshSample, let att = lastAttitude else { return }
        yawZero = wrappedDegrees(-att.yaw.degrees)
        isCalibrated = true
        calibrationState = .manual
        pose.yaw = 0
        pose.yawCalibrated = true
        log.notice("manual yaw recenter")
        didRecenter.send()
    }

    private var freshSample: Bool {
        status.isTracking && motionDataFresh && delivery.isFresh(at: ProcessInfo.processInfo.systemUptime)
    }

    private func invalidateCalibration(resetDelivery: Bool = true) {
        if resetDelivery { delivery = MotionDelivery() }
        motionDataFresh = false
        calibrationEpoch += 1
        reference = nil
        recoveryAttitudes.removeAll(keepingCapacity: true)
        yawZero = nil
        lastAttitude = nil
        isCalibrated = false
        isPostureCalibrated = false
        calibrationState = quietRecoveryEnabled ? .waitingForActivity : .needsForward
        recoveryReason = .activity
        recovery = QuietRecovery()
        continuity = MotionContinuity()
        pose = .zero
        didInvalidateCalibration.send()
    }

    private func handle(_ motion: CMDeviceMotion) {
        let now = ProcessInfo.processInfo.systemUptime
        let yaw = -motion.attitude.yaw.degrees
        let speed = sqrt(pow(motion.rotationRate.x, 2) + pow(motion.rotationRate.y, 2) + pow(motion.rotationRate.z, 2)).degrees
        let acceleration = sqrt(pow(motion.userAcceleration.x, 2) + pow(motion.userAcceleration.y, 2) + pow(motion.userAcceleration.z, 2))
        guard [yaw, motion.attitude.pitch, motion.attitude.roll, speed, acceleration, motion.timestamp].allSatisfy(\.isFinite) else {
            invalidateCalibration()
            status = .waitingForHeadphones
            reconnectSchedule.request(at: now, delay: 3)
            return
        }
        guard delivery.state != .expired else { return }
        if !continuity.accept(timestamp: motion.timestamp, arrival: now,
                              side: motion.sensorLocation.rawValue, yaw: yaw, speed: speed,
                              pitch: motion.attitude.pitch.degrees, roll: motion.attitude.roll.degrees) {
            let clockReset = delivery.lastTimestamp.map { motion.timestamp <= $0 } ?? false
            invalidateCalibration(resetDelivery: clockReset)
            _ = continuity.accept(timestamp: motion.timestamp, arrival: now,
                                  side: motion.sensorLocation.rawValue, yaw: yaw, speed: speed,
                                  pitch: motion.attitude.pitch.degrees, roll: motion.attitude.roll.degrees)
        }
        let side = SensorSide(motion.sensorLocation)
        if status != .tracking(side) { status = .tracking(side) }
        let deliveryState = delivery.receive(timestamp: motion.timestamp, arrival: now)
        if deliveryState == .expired {
            expireMotion(at: now)
            return
        }
        guard deliveryState == .fresh else {
            pauseMotion()
            recordDiagnostics(motion, at: now, pose: nil)
            return
        }
        if !motionDataFresh, reference != nil {
            log.notice("motion delivery resumed with retained reference: epoch=\(self.calibrationEpoch)")
        }
        motionDataFresh = true
        reconnectSchedule.receivedSample()
        reconnectExhausted = false
        isReconnecting = false
        lastAttitude = motion.attitude.copy() as? CMAttitude
        lastError = nil

        let interaction = InteractionSignal.latest(at: now)
        if yawZero == nil, quietRecoveryEnabled {
            recoveryAttitudes.removeAll { now - $0.time > 16 }
            if recoveryAttitudes.count >= 4096 { recoveryAttitudes.removeFirst() }
            recoveryAttitudes.append((now, lastAttitude!))
            if let center = recovery.update(.init(time: now, yaw: yaw, pitch: motion.attitude.pitch.degrees,
                                                   roll: motion.attitude.roll.degrees, rotationSpeed: speed,
                                                   acceleration: acceleration, lastInteraction: interaction)) {
                yawZero = center
                guard let representative = recoveryAttitudes.first(where: { $0.time == recovery.referenceTime }),
                      let captured = representative.attitude.copy() as? CMAttitude else {
                    invalidateCalibration()
                    return
                }
                reference = captured
                isCalibrated = true
                isPostureCalibrated = reference != nil
                recoveryAttitudes.removeAll(keepingCapacity: true)
                calibrationState = .automatic
                didRecenter.send()
                log.notice("quiet direction and posture recovery completed")
            } else {
                calibrationState = recovery.state == .waitingForActivity ? .waitingForActivity : .recovering
            }
            if recoveryReason != recovery.reason,
               recovery.state != .collecting || now - recoveryReasonUpdatedAt >= 0.75 {
                recoveryReason = recovery.reason
                recoveryReasonUpdatedAt = now
            }
        }

        let att = motion.attitude.copy() as! CMAttitude
        if let reference { att.multiply(byInverseOf: reference) }
        var p = HeadPose(attitude: att, timestamp: motion.timestamp)
        p.applyReferenceValidity(hasReference: reference != nil, yawZero: yawZero, rawYaw: yaw)
        pose = p
        samples.send(p)
        recordDiagnostics(motion, at: now, pose: p)
    }

    private func pauseMotion() {
        if motionDataFresh {
            motionDataFresh = false
            pose.yawCalibrated = false
            pose.postureCalibrated = false
            didPauseMotion.send()
            log.notice("motion delivery paused; retaining reference")
        }
        if !isCalibrated {
            recovery = QuietRecovery()
            recoveryAttitudes.removeAll(keepingCapacity: true)
            calibrationState = quietRecoveryEnabled ? .waitingForActivity : .needsForward
            recoveryReason = .activity
        }
    }

    private func expireMotion(at now: TimeInterval) {
        invalidateCalibration(resetDelivery: false)
        status = .waitingForHeadphones
        reconnectSchedule.request(at: now)
        log.notice("motion delivery expired; reference invalidated")
    }

    private func recordDiagnostics(_ motion: CMDeviceMotion, at now: TimeInterval, pose p: HeadPose?) {
        let interaction = InteractionSignal.latest(at: now)
        diagnostics.record(.init(time: now, sensorTime: motion.timestamp, epoch: calibrationEpoch,
                                 rawYaw: -motion.attitude.yaw.degrees, yaw: p?.yaw ?? 0,
                                 rawPitch: motion.attitude.pitch.degrees, rawRoll: motion.attitude.roll.degrees,
                                 rotationX: motion.rotationRate.x.degrees,
                                 rotationY: motion.rotationRate.y.degrees,
                                 rotationZ: motion.rotationRate.z.degrees,
                                 acceleration: sqrt(pow(motion.userAcceleration.x, 2) + pow(motion.userAcceleration.y, 2) + pow(motion.userAcceleration.z, 2)),
                                 side: motion.sensorLocation.rawValue,
                                 yawValid: p?.yawCalibrated ?? false, postureValid: p?.postureCalibrated ?? false,
                                 mode: String(describing: calibrationState),
                                 activityAge: interaction.map { now - $0 },
                                 recoveryReason: calibrationState == .manual ? "manual" : recovery.reason.rawValue,
                                 recoveryWindows: calibrationState == .manual ? 0 : recovery.completedWindows,
                                 relativePitch: p.flatMap { $0.postureCalibrated ? $0.pitch : nil },
                                 referenceSource: isPostureCalibrated ? (calibrationState == .manual ? "manual" : "stable-window-sample") : "none",
                                 deliveryState: delivery.state.rawValue, deliveryLag: delivery.lag))
    }

    private func observeWorkspace() {
        let pairs: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screen"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ]
        for (pause, resume, reason) in pairs {
            let center = NSWorkspace.shared.notificationCenter
            workspaceObservers.append(center.addObserver(forName: pause, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.suspensionReasons.insert(reason)
                self.stop()
            })
            workspaceObservers.append(center.addObserver(forName: resume, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.suspensionReasons.remove(reason)
                if self.suspensionReasons.isEmpty { self.start() }
            })
        }
    }

    private var routeTick = 0

    private func checkStale() {
        let now = ProcessInfo.processInfo.systemUptime
        if status.isTracking {
            switch delivery.poll(at: now) {
            case .expired: expireMotion(at: now)
            case .delayed, .settling: pauseMotion()
            case .fresh: break
            }
        }
        if isReconnecting, now >= manualReconnectUntil { isReconnecting = false }
        routeTick += 1
        if routeTick % 4 == 0 { refreshAudioRoute() }
        guard suspensionReasons.isEmpty, !status.isTracking,
              authorization == .authorized, bluetoothAudioPresent || connectedByDelegate else { return }
        if now - lastRebuildAt >= 5, reconnectSchedule.takeDueAttempt(at: now) {
            log.notice("recovering motion stream: attempt \(self.reconnectSchedule.attempts)")
            rebuildSession()
        }
        reconnectExhausted = reconnectSchedule.exhausted
    }

    private func refreshAudioRoute() {
        let snapshot = AudioRoute.snapshot()
        guard snapshot.isKnown else { return }
        let previous = routeSnapshot
        routeSnapshot = snapshot
        bluetoothAudioPresent = snapshot.hasBluetoothAudio
        headphonesRoutedAway = !snapshot.hasBluetoothAudio
        guard suspensionReasons.isEmpty, !status.isTracking, authorization == .authorized else { return }
        reconnectSchedule.routeChanged(from: previous, to: snapshot, at: ProcessInfo.processInfo.systemUptime)
        reconnectExhausted = reconnectSchedule.exhausted
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CMHeadphoneMotionManager.authorizationStatus()
            guard now != .notDetermined else { return }
            self.permissionTimer?.invalidate(); self.permissionTimer = nil
            self.refreshStatus()
            log.notice("permission poll: now=\(now.rawValue)")
            if now == .authorized {
                self.rebuildSession()
            }
        }
    }

    private func refreshStatus() {
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        if authorization != auth { authorization = auth }
        if !manager.isDeviceMotionAvailable { invalidateCalibration(); status = .unsupported; return }
        if auth != .authorized { invalidateCalibration() }
        switch auth {
        case .denied: status = .denied
        case .restricted: status = .restricted
        case .notDetermined: status = .waitingForPermission
        case .authorized:
            if !status.isTracking { status = .waitingForHeadphones }
        @unknown default: status = .waitingForPermission
        }
    }
}

extension HeadTracker: CMHeadphoneMotionManagerDelegate {
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        log.notice("delegate: didConnect")
        DispatchQueue.main.async { [weak self] in
            guard let self, manager === self.manager, self.suspensionReasons.isEmpty else { return }
            self.connectedByDelegate = true
            self.refreshStatus()
            if !self.status.isTracking {
                self.reconnectSchedule.request(at: ProcessInfo.processInfo.systemUptime, delay: 3)
            }
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        log.notice("delegate: didDisconnect")
        DispatchQueue.main.async { [weak self] in
            guard let self, manager === self.manager, self.suspensionReasons.isEmpty else { return }
            self.connectedByDelegate = false
            self.invalidateCalibration()
            self.status = .waitingForHeadphones
            self.reconnectSchedule.request(at: ProcessInfo.processInfo.systemUptime, delay: 3)
        }
    }
}
