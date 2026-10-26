// Fake HAL: exercises the production service without touching any real audio device.
import CoreAudio
import Foundation

class BoringNotchXPCHelper: NSObject {}

private enum HAL {
    static var native = true
    static var mute: UInt32 = 0
    static var gain: Float32 = 0.37
    static var failWrite = false
    static var device: AudioDeviceID = 9001
}

func AudioObjectHasProperty(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>) -> Bool {
    address.pointee.mSelector == kAudioDevicePropertyMute ? HAL.native : true
}
func AudioObjectIsPropertySettable(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ settable: UnsafeMutablePointer<DarwinBoolean>) -> OSStatus {
    settable.pointee = DarwinBoolean(address.pointee.mSelector != kAudioDevicePropertyMute || HAL.native)
    return noErr
}
func AudioObjectGetPropertyDataSize(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>) -> OSStatus { -1 }
func AudioObjectGetPropertyData(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>, _ data: UnsafeMutableRawPointer) -> OSStatus {
    switch address.pointee.mSelector {
    case kAudioHardwarePropertyDefaultInputDevice: data.storeBytes(of: HAL.device, as: AudioDeviceID.self)
    case kAudioObjectPropertyName, kAudioDevicePropertyDeviceUID:
        data.storeBytes(of: Unmanaged.passRetained("notch-test-\(HAL.device)" as CFString), as: Unmanaged<CFString>.self)
    case kAudioDevicePropertyMute: data.storeBytes(of: HAL.mute, as: UInt32.self)
    case kAudioDevicePropertyVolumeScalar: data.storeBytes(of: HAL.gain, as: Float32.self)
    default: return -1
    }
    return noErr
}
func AudioObjectSetPropertyData(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UInt32, _ data: UnsafeRawPointer) -> OSStatus {
    if HAL.failWrite { return -1 }
    switch address.pointee.mSelector {
    case kAudioDevicePropertyMute: HAL.mute = data.load(as: UInt32.self)
    case kAudioDevicePropertyVolumeScalar: HAL.gain = data.load(as: Float32.self)
    default: return -1
    }
    return noErr
}

@main struct MicrophoneMutationChecks {
    static func main() throws {
        let helper = BoringNotchXPCHelper()
        func toggle() -> [String: Any] {
            let semaphore = DispatchSemaphore(value: 0)
            var result: [String: Any] = [:]
            helper.toggleMicrophone { data in
                result = (try? JSONSerialization.jsonObject(with: data!)) as! [String: Any]
                semaphore.signal()
            }
            precondition(semaphore.wait(timeout: .now() + 5) == .success)
            return result
        }
        precondition(toggle()["muted"] as? Bool == true && HAL.mute == 1)
        precondition(toggle()["muted"] as? Bool == false && HAL.mute == 0)
        HAL.failWrite = true
        precondition(toggle()["error"] as? String == "writeFailed" && HAL.mute == 0)
        HAL.failWrite = false
        HAL.native = false
        let key = "microphoneGainBeforeMute.notch-test-9001"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        precondition(toggle()["muted"] as? Bool == true && HAL.gain == 0)
        precondition(toggle()["muted"] as? Bool == false && abs(HAL.gain - 0.37) < 0.001, "Unmute must restore the original input gain")
        HAL.gain = 0
        precondition(toggle()["error"] as? String == "noSavedGain" && HAL.gain == 0, "External mute must not invent a gain")
        HAL.gain = 0.61
        _ = toggle()
        HAL.device = 9002
        precondition(toggle()["error"] as? String == "noSavedGain" && HAL.gain == 0, "A different device must not inherit saved gain")
        HAL.device = 0
        precondition(toggle()["error"] as? String == "noInput")
        print("Microphone mutation checks passed (fake HAL; no hardware changed)")
    }
}
