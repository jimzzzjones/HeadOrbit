import Combine
import Foundation

/// 一个「头部动作 → 本地功能」的插件。后续想加新功能（比如低头暂停视频、转头切歌）就再实现一个。
protocol HeadAction: AnyObject {
    var id: String { get }
    var title: String { get }
    var isEnabled: Bool { get set }
    var needsPostureCalibration: Bool { get }

    /// 每一帧姿态都会调到这里（主线程）
    func process(_ pose: HeadPose)
    /// 追踪中断（摘下耳机 / 断连 / 关闭）或用户重新校准时调用：清掉计时器、提醒、暂停，回到初始状态
    func reset()
}

/// 把 HeadTracker 的数据分发给所有动作
final class ActionEngine: ObservableObject {
    let actions: [HeadAction]
    private var bag = Set<AnyCancellable>()

    convenience init(tracker: HeadTracker, actions: [HeadAction]) {
        self.init(samples: tracker.samples.eraseToAnyPublisher(),
                  tracking: tracker.$status.map(\.isTracking).eraseToAnyPublisher(),
                  resets: Publishers.Merge(tracker.didRecenter, tracker.didInvalidateCalibration).eraseToAnyPublisher(),
                  actions: actions)
    }

    init(samples: AnyPublisher<HeadPose, Never>, tracking: AnyPublisher<Bool, Never>,
         resets: AnyPublisher<Void, Never>, actions: [HeadAction]) {
        self.actions = actions
        samples.sink { [weak self] pose in
            self?.actions.forEach {
                if $0.isEnabled && ($0.needsPostureCalibration ? pose.postureCalibrated : pose.yawCalibrated) {
                    $0.process(pose)
                } else { $0.reset() }
            }
        }.store(in: &bag)
        tracking.removeDuplicates().sink { [weak self] isTracking in
            if !isTracking { self?.actions.forEach { $0.reset() } }
        }.store(in: &bag)
        resets.sink { [weak self] in self?.actions.forEach { $0.reset() } }.store(in: &bag)
    }
}
