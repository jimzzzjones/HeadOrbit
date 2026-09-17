import CoreAudio
import Foundation

struct AudioRouteSnapshot: Equatable {
    var isKnown = true
    var bluetoothDevices: Set<AudioObjectID>
    var defaultInput: AudioObjectID
    var defaultOutput: AudioObjectID
    var hasBluetoothAudio: Bool { !bluetoothDevices.isEmpty }
}

enum AudioRoute {
    static func snapshot() -> AudioRouteSnapshot {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        var ids: [AudioObjectID] = []
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return AudioRouteSnapshot(isKnown: false, bluetoothDevices: [], defaultInput: 0, defaultOutput: 0)
        }
        do {
            ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) != noErr {
                return AudioRouteSnapshot(isKnown: false, bluetoothDevices: [], defaultInput: 0, defaultOutput: 0)
            }
        }
        let bluetooth = ids.filter {
            isBluetooth($0) && (hasStreams($0, scope: kAudioDevicePropertyScopeOutput) ||
                                hasStreams($0, scope: kAudioDevicePropertyScopeInput))
        }
        return AudioRouteSnapshot(bluetoothDevices: Set(bluetooth),
                                  defaultInput: systemDevice(kAudioHardwarePropertyDefaultInputDevice),
                                  defaultOutput: systemDevice(kAudioHardwarePropertyDefaultOutputDevice))
    }

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func systemDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var addr = address(selector)
        var result = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &result) == noErr else { return 0 }
        return result
    }

    private static func isBluetooth(_ id: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyTransportType)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var transport: UInt32 = 0
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func hasStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }
}

final class AudioRouteMonitor {
    private let selectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
        kAudioHardwarePropertyDefaultOutputDevice
    ]
    private var listeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        for selector in selectors {
            var addr = AudioRoute.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.schedule() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block) == noErr {
                listeners.append((selector, block))
            }
        }
    }

    deinit {
        pending?.cancel()
        for (selector, block) in listeners {
            var addr = AudioRoute.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        }
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}
