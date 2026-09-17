import Foundation

struct MotionDelivery {
    enum State: String { case settling, fresh, delayed, expired }
    static let pauseAfter: TimeInterval = 0.5
    static let expireAfter: TimeInterval = 5
    private(set) var state: State = .settling
    private(set) var lag: TimeInterval = 0
    private(set) var lastTimestamp: TimeInterval?
    private var clockOffset: TimeInterval?
    private var firstArrival: TimeInterval?
    private var lastArrival: TimeInterval?
    private var lastFreshArrival: TimeInterval?
    private var freshSince: TimeInterval?
    private var settlingOffset: TimeInterval?

    mutating func receive(timestamp: TimeInterval, arrival: TimeInterval) -> State {
        guard state != .expired else { return state }
        guard timestamp.isFinite, arrival.isFinite,
              lastArrival.map({ arrival >= $0 }) ?? true,
              lastTimestamp.map({ timestamp > $0 }) ?? true else {
            state = .expired
            return state
        }
        if firstArrival == nil { firstArrival = arrival }
        if hasExpired(at: arrival) { state = .expired; return state }
        let arrivalGap = lastArrival.map { arrival - $0 } ?? 0
        let previousAge = arrivalGap + lag
        let offset = arrival - timestamp
        // A late callback must never move the clock anchor forward and normalize its own backlog.
        if let previous = clockOffset, offset < previous - 0.05 { freshSince = nil }
        clockOffset = min(clockOffset ?? offset, offset)
        if state != .fresh, let settlingOffset, clockOffset! < settlingOffset - 0.02 { freshSince = nil }
        lag = max(0, offset - clockOffset!)
        lastTimestamp = timestamp
        lastArrival = arrival
        if previousAge > Self.pauseAfter || lag > 0.2 {
            freshSince = nil
            state = .delayed
        } else {
            if freshSince == nil {
                freshSince = arrival
                settlingOffset = clockOffset
            }
            if arrival - freshSince! >= 0.25 {
                state = .fresh
                lastFreshArrival = arrival
            } else {
                state = .settling
            }
        }
        return state
    }

    mutating func poll(at now: TimeInterval) -> State {
        guard state != .expired else { return state }
        guard now.isFinite, lastArrival.map({ now >= $0 }) ?? true else {
            state = .expired
            return state
        }
        if hasExpired(at: now) { state = .expired }
        else if let lastArrival, now - lastArrival + lag > Self.pauseAfter {
            freshSince = nil
            state = .delayed
        }
        return state
    }

    func isFresh(at now: TimeInterval) -> Bool {
        state == .fresh && MotionContinuity.sampleIsFresh(isTracking: true, lastArrival: lastArrival.map { $0 - lag }, now: now)
    }

    private func hasExpired(at now: TimeInterval) -> Bool {
        (lastFreshArrival ?? firstArrival).map { now - $0 >= Self.expireAfter } ?? false
    }
}
