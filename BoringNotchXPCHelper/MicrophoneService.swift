import CoreAudio
import Foundation

private struct MicrophoneReading: Codable {
    var name = ""
    var muted: Bool?
    var canToggle = false
    var error: String?
}

extension BoringNotchXPCHelper {
    private static let microphoneQueue = DispatchQueue(label: "boringNotch.microphone")

    @objc func microphoneStatus(with reply: @escaping (Data?) -> Void) {
        Self.microphoneQueue.async { reply(try? JSONEncoder().encode(Self.readMicrophone(toggle: false))) }
    }

    @objc func toggleMicrophone(with reply: @escaping (Data?) -> Void) {
        Self.microphoneQueue.async { reply(try? JSONEncoder().encode(Self.readMicrophone(toggle: true))) }
    }

    private static func readMicrophone(toggle: Bool) -> MicrophoneReading {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != kAudioObjectUnknown else { return MicrophoneReading(error: "noInput") }
        let name = audioString(device, selector: kAudioObjectPropertyName) ?? ""
        let uid = audioString(device, selector: kAudioDevicePropertyDeviceUID) ?? String(device)
        var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if writable(device, &mute), AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &muted) == noErr {
            if toggle {
                var next: UInt32 = muted == 0 ? 1 : 0
                guard AudioObjectSetPropertyData(device, &mute, 0, nil, size, &next) == noErr else { return MicrophoneReading(name: name, muted: muted != 0, canToggle: true, error: "writeFailed") }
                return readMicrophone(toggle: false)
            }
            return MicrophoneReading(name: name, muted: muted != 0, canToggle: true)
        }

        let channels = volumeChannels(device)
        guard !channels.isEmpty else { return MicrophoneReading(name: name, error: "unsupported") }
        var values: [String: Float] = [:]
        for channel in channels {
            var volume = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: channel)
            var level: Float32 = 0
            size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &volume, 0, nil, &size, &level) == noErr else { return MicrophoneReading(name: name, error: "readFailed") }
            values[String(channel)] = level
        }
        let isMuted = values.values.allSatisfy { $0 == 0 }
        guard toggle else { return MicrophoneReading(name: name, muted: isMuted, canToggle: true) }
        let key = "microphoneGainBeforeMute." + uid
        let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: NSNumber]
        if isMuted && (saved == nil || channels.contains { saved?[String($0)] == nil }) {
            return MicrophoneReading(name: name, muted: true, canToggle: true, error: "noSavedGain")
        }
        if !isMuted { UserDefaults.standard.set(values, forKey: key) }
        var changed: [AudioObjectPropertyElement] = []
        for channel in channels {
            var volume = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: channel)
            // Never invent an input gain when the user muted outside this app.
            guard let target = isMuted ? saved?[String(channel)]?.floatValue : 0 else { return MicrophoneReading(name: name, muted: isMuted, canToggle: true, error: "noSavedGain") }
            var level = target
            if AudioObjectSetPropertyData(device, &volume, 0, nil, size, &level) != noErr {
                for previous in changed {
                    var rollback = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: previous)
                    var original = values[String(previous)] ?? 0
                    _ = AudioObjectSetPropertyData(device, &rollback, 0, nil, size, &original)
                }
                return MicrophoneReading(name: name, error: "writeFailed")
            }
            changed.append(channel)
        }
        if isMuted { UserDefaults.standard.removeObject(forKey: key) }
        return readMicrophone(toggle: false)
    }

    private static func audioString(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func writable(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address) && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func volumeChannels(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var master = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        if writable(device, &master) { return [kAudioObjectPropertyElementMain] }
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size else { return [] }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &streams, 0, nil, &size, storage) == noErr else { return [] }
        let count = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
        guard count > 0 else { return [] }
        let channels = (1...count).map { AudioObjectPropertyElement($0) }
        guard channels.allSatisfy({ channel in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: channel)
            return writable(device, &address)
        }) else { return [] }
        return channels
    }
}
