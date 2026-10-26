// Run via scripts/tests/check-device-controls.sh; this harness never changes microphone state.
import Foundation

class BoringNotchXPCHelper: NSObject {}

@main struct DeviceControlsChecks {
    static func main() throws {
        let fixture: [String: Any] = ["SPBluetoothDataType": [[
            "device_connected": [
                ["Board": ["device_address": "keyboard", "device_minorType": "Keyboard"]],
                ["Buds": ["device_address": "headphones", "device_minorType": "Headphones", "device_batteryLevelLeft": "12%", "device_batteryLevelRight": "90%", "device_batteryLevelCase": "100%"]],
                ["Mouse": ["device_minorType": "Mouse", "device_batteryLevelMain": "80%"]],
                ["Unknown board": ["device_minorType": "Keyboard", "device_batteryLevelMain": "101%"]]
            ],
            "device_not_connected": [["Old buds": ["device_minorType": "Headphones", "device_batteryLevelMain": "50%"]]]
        ]]]
        let input = try JSONSerialization.data(withJSONObject: fixture)
        let output = BoringNotchXPCHelper.parsePeripheralBatteries(input, hid: ["Board": 67])!
        let devices = try JSONSerialization.jsonObject(with: output) as! [[String: Any]]
        precondition(devices.count == 3, "Only connected keyboards and headphones should be shown")
        let keyboard = devices.first { $0["name"] as? String == "Board" }!
        precondition((keyboard["levels"] as? [String: Int])?["main"] == 67)
        let buds = devices.first { $0["name"] as? String == "Buds" }!
        precondition((buds["levels"] as? [String: Int]) == ["left": 12, "right": 90, "case": 100])
        let unknown = devices.first { $0["name"] as? String == "Unknown board" }!
        precondition((unknown["levels"] as? [String: Int])?.isEmpty == true, "Unknown battery is not 0%")
        precondition(BoringNotchXPCHelper.parsePeripheralBatteries(Data("bad json".utf8), hid: [:]) == nil)
        print("Battery parsing checks passed")

        let semaphore = DispatchSemaphore(value: 0)
        BoringNotchXPCHelper().microphoneStatus { data in
            if let data, let text = String(data: data, encoding: .utf8) { print("Read-only microphone snapshot:", text) }
            else { fatalError("Microphone status did not return valid data") }
            semaphore.signal()
        }
        precondition(semaphore.wait(timeout: .now() + 10) == .success)
        BoringNotchXPCHelper().peripheralBatteries { data in
            guard let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                fatalError("Could not read real Bluetooth snapshot")
            }
            print("Read-only Bluetooth snapshot: \(list.count) supported connected device(s)")
            semaphore.signal()
        }
        precondition(semaphore.wait(timeout: .now() + 20) == .success)

    }
}
