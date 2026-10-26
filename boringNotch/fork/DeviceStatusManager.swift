import Combine
import Defaults
import Foundation
import KeyboardShortcuts

struct PeripheralBattery: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
    let levels: [String: Int]

    var symbol: String { kind == "keyboard" ? "keyboard" : "headphones" }
    var percent: Int? {
        // The case should not hide a low earbud battery.
        let earbuds = [levels["left"], levels["right"]].compactMap { $0 }
        return earbuds.min() ?? levels["main"] ?? levels["case"]
    }
}

struct MicrophoneReading: Decodable, Equatable {
    var name = ""
    var muted: Bool?
    var canToggle = false
    var error: String?
}

@MainActor
final class DeviceStatusManager: ObservableObject {
    static let shared = DeviceStatusManager()

    @Published private(set) var peripherals: [PeripheralBattery] = []
    @Published private(set) var batteryUnavailable = false
    @Published private(set) var microphone = MicrophoneReading()
    @Published private(set) var isToggling = false
    @Published private(set) var microphoneNotice: String?

    private var batteryTimer: Timer?
    private var microphoneTimer: Timer?
    private var batteryTask: Task<Void, Never>?
    private var microphoneTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var watchers = 0

    private init() {}

    func start() {
        guard microphoneTimer == nil else { return }
        KeyboardShortcuts.onKeyDown(for: .toggleMicrophoneMute) { Self.shared.toggleMicrophone() }
        refreshMicrophone()
        microphoneTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in Self.shared.refreshMicrophone() }
        }
    }

    func startWatchingBatteries() {
        watchers += 1
        guard batteryTimer == nil else { return }
        refreshBatteries()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in Self.shared.refreshBatteries() }
        }
    }

    func stopWatchingBatteries() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    func refreshBatteries() {
        guard batteryTask == nil, Defaults[.showPeripheralBatteries] else { return }
        batteryTask = Task {
            defer { batteryTask = nil }
            guard let data = await XPCHelperClient.shared.peripheralBatteries(),
                  let devices = try? JSONDecoder().decode([PeripheralBattery].self, from: data) else {
                peripherals = []
                batteryUnavailable = true
                return
            }
            peripherals = devices.sorted { ($0.kind, $0.name, $0.id) < ($1.kind, $1.name, $1.id) }
            batteryUnavailable = false
        }
    }

    func refreshMicrophone() {
        guard microphoneTask == nil, !isToggling else { return }
        microphoneTask = Task {
            defer { microphoneTask = nil }
            let data = await XPCHelperClient.shared.microphoneStatus()
            // A read started before a toggle must not replace its result.
            guard !isToggling else { return }
            updateMicrophone(data)
        }
    }

    func toggleMicrophone() {
        guard !isToggling else { return }
        isToggling = true
        Task {
            // Finish a pending status read before issuing the mutation.
            await microphoneTask?.value
            let data = await XPCHelperClient.shared.toggleMicrophone()
            updateMicrophone(data)
            isToggling = false
            if microphone.error == nil, let muted = microphone.muted {
                showNotice(muted ? String(localized: "Microphone muted") : String(localized: "Microphone unmuted"))
            } else {
                showNotice(microphoneError)
            }
        }
    }

    private func updateMicrophone(_ data: Data?) {
        guard let data, let reading = try? JSONDecoder().decode(MicrophoneReading.self, from: data) else {
            microphone = MicrophoneReading(error: "readFailed")
            return
        }
        microphone = reading
    }

    var microphoneError: String {
        switch microphone.error {
        case "noInput": return String(localized: "No input device")
        case "unsupported": return String(localized: "This input device does not support system mute or input gain control")
        case "noSavedGain": return String(localized: "Input gain is zero. Restore it in Sound settings before using mute here.")
        case "writeFailed": return String(localized: "Could not change microphone state")
        default: return String(localized: "Could not read microphone state")
        }
    }

    private func showNotice(_ text: String) {
        noticeTask?.cancel()
        microphoneNotice = text
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            microphoneNotice = nil
        }
    }
}
