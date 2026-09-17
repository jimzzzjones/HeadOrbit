import Foundation

struct ReconnectSchedule {
    private(set) var attempts = 0
    private(set) var nextAttemptAt: TimeInterval?
    var exhausted: Bool { attempts == 3 && nextAttemptAt == nil }

    mutating func routeChanged(from previous: AudioRouteSnapshot?, to current: AudioRouteSnapshot,
                               at time: TimeInterval) {
        guard current.isKnown, previous?.isKnown != false, current.hasBluetoothAudio else { return }
        if let previous {
            let inputReturned = current.bluetoothDevices.contains(current.defaultInput) &&
                (current.defaultInput != previous.defaultInput ||
                 !previous.bluetoothDevices.contains(previous.defaultInput))
            let outputReturned = current.bluetoothDevices.contains(current.defaultOutput) &&
                (current.defaultOutput != previous.defaultOutput ||
                 !previous.bluetoothDevices.contains(previous.defaultOutput))
            // Audio devices can remain enumerated while AirPods are serving another host.
            if !previous.hasBluetoothAudio || inputReturned || outputReturned {
                self = ReconnectSchedule()
            }
        }
        if current != previous { request(at: time, delay: previous == nil ? 12 : 1) }
    }

    mutating func request(at time: TimeInterval, delay: TimeInterval = 1) {
        // A repeated Core Motion connect callback must not postpone or refill the retry budget.
        guard attempts == 0, nextAttemptAt == nil else { return }
        nextAttemptAt = time + delay
    }

    mutating func takeDueAttempt(at time: TimeInterval) -> Bool {
        guard let nextAttemptAt, time >= nextAttemptAt, attempts < 3 else { return false }
        attempts += 1
        switch attempts {
        case 1: self.nextAttemptAt = time + 12
        case 2: self.nextAttemptAt = time + 25
        default: self.nextAttemptAt = nil
        }
        return true
    }

    mutating func receivedSample() { self = ReconnectSchedule() }
}
