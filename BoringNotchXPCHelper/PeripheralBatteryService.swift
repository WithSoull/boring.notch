import Foundation
import IOKit

extension BoringNotchXPCHelper {
    @objc func peripheralBatteries(with reply: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "mini"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { reply(nil); return }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationStatus == 0 else { reply(nil); return }
            reply(Self.parsePeripheralBatteries(data, hid: Self.hidBatteryLevels()))
        }
    }

    static func parsePeripheralBatteries(_ data: Data, hid: [String: Int]) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        var devices: [[String: Any]] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, properties) in entry {
                    guard let properties = properties as? [String: Any] else { continue }
                    let type = (properties["device_minorType"] as? String ?? "").lowercased()
                    let kind: String
                    if type.contains("keyboard") { kind = "keyboard" }
                    else if type.contains("head") || type.contains("audio") || name.lowercased().contains("airpods") { kind = "headphones" }
                    else { continue }
                    var levels: [String: Int] = [:]
                    for (key, label) in [("device_batteryLevelMain", "main"), ("device_batteryLevelLeft", "left"), ("device_batteryLevelRight", "right"), ("device_batteryLevelCase", "case")] {
                        if let value = Self.batteryPercent(properties[key]) { levels[label] = value }
                    }
                    if levels.isEmpty, let value = hid[name] { levels["main"] = value }
                    devices.append(["id": properties["device_address"] as? String ?? name, "name": name, "kind": kind, "levels": levels])
                }
            }
        }
        return try? JSONSerialization.data(withJSONObject: devices)
    }

    static func batteryPercent(_ value: Any?) -> Int? {
        let number: Int?
        if let value = value as? String { number = Int(value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
        else { number = (value as? NSNumber)?.intValue }
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }

    private static func hidBatteryLevels() -> [String: Int] {
        var result: [String: Int] = [:]
        for className in ["AppleDeviceManagementHIDEventService", "IOHIDDevice"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let values = properties?.takeRetainedValue() as? [String: Any],
                      let name = values["Product"] as? String,
                      let percent = batteryPercent(values["BatteryPercent"]) else { continue }
                result[name] = percent
            }
        }
        return result
    }
}
