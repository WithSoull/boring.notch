import Defaults
import KeyboardShortcuts
import SwiftUI

/// Header button that mutes the default input device.
struct MicrophoneHeaderButton: View {
    @ObservedObject private var devices = DeviceStatusManager.shared
    @Default(.showMicrophoneButton) private var showMicrophone

    var body: some View {
        if showMicrophone {
            Button { devices.toggleMicrophone() } label: {
                Image(systemName: devices.microphone.error != nil ? "mic.badge.xmark" : devices.microphone.muted == true ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(devices.microphone.error != nil ? .yellow : devices.microphone.muted == true ? .red : .white)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(devices.isToggling)
            .help(microphoneHelp)
            .accessibilityLabel(devices.microphone.muted == true ? Text("Unmute microphone") : Text("Mute microphone"))
        }
    }

    private var microphoneHelp: String {
        if devices.microphone.error != nil { return devices.microphoneError }
        let action = devices.microphone.muted == true ? String(localized: "Unmute microphone") : String(localized: "Mute microphone")
        return devices.microphone.name.isEmpty ? action : "\(action) · \(devices.microphone.name)"
    }
}

/// Header: charge of connected Bluetooth keyboards and headphones; click for details.
struct PeripheralBatteriesHeader: View {
    @ObservedObject private var devices = DeviceStatusManager.shared
    @Default(.showPeripheralBatteries) private var showBatteries
    @State private var showDetails = false

    var body: some View {
        if showBatteries {
            Button { showDetails.toggle() } label: {
                HStack(spacing: 10) {
                    ForEach(Array(devices.peripherals.prefix(3))) { device in
                        batteryLabel(device)
                    }
                    if devices.peripherals.isEmpty {
                        Image(systemName: "keyboard").foregroundStyle(.gray)
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .fixedSize()
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bluetooth device batteries")
            .popover(isPresented: $showDetails) { batteryDetails }
            .onAppear { devices.startWatchingBatteries() }
            .onDisappear { devices.stopWatchingBatteries() }
        }
    }

    private func batteryLabel(_ device: PeripheralBattery) -> some View {
        HStack(spacing: 3) {
            Image(systemName: device.symbol)
            Text(device.shortText)
                .monospacedDigit()
        }
        .foregroundStyle((device.percent ?? 100) <= 20 ? .yellow : .white)
        .help(device.name)
        .accessibilityLabel(Text(device.name + ": " + (device.percent.map { "\($0)%" } ?? String(localized: "Battery unavailable"))))
    }

    private var batteryDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bluetooth batteries").font(.headline)
                Spacer()
                Button { devices.refreshBatteries() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .help("Refresh batteries")
            }
            if devices.batteryUnavailable {
                Text("Could not read Bluetooth devices").foregroundStyle(.secondary)
            } else if devices.peripherals.isEmpty {
                Text("No connected keyboards or headphones").foregroundStyle(.secondary)
            }
            ForEach(devices.peripherals) { device in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: device.symbol).frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                        if device.levels.isEmpty {
                            Text("macOS does not report this device’s battery level")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(["main", "half2", "left", "right", "case"], id: \.self) { part in
                                if let level = device.levels[part] {
                                    HStack {
                                        Text(partLabel(part, in: device))
                                        Spacer()
                                        Text("\(level)%").monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func partLabel(_ part: String, in device: PeripheralBattery) -> String {
        switch part {
        case "main" where device.levels["half2"] != nil: return String(localized: "Main half")
        case "half2": return String(localized: "Second half")
        case "left": return String(localized: "Left earbud")
        case "right": return String(localized: "Right earbud")
        case "case": return String(localized: "Charging case")
        default: return String(localized: "Battery")
        }
    }
}

/// Small red mic shown on closed-notch activities while the default input is muted.
struct MicMutedBadge: View {
    @ObservedObject private var devices = DeviceStatusManager.shared
    var size: CGFloat = 11

    var body: some View {
        if devices.microphone.muted == true {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.red)
                .help(devices.microphone.name)
        }
    }
}

/// Closed-notch activity: the microphone notice after a toggle, or "Muted" while nothing else is shown.
struct MicrophoneActivity: View {
    let notice: String?
    @ObservedObject private var devices = DeviceStatusManager.shared

    var body: some View {
        ClosedNotchSidesView(showsMicBadge: false) {
            Image(systemName: devices.microphone.muted == true ? "mic.slash.fill" : "mic.fill")
                .foregroundStyle(devices.microphone.muted == true ? .red : .white)
            Text(devices.microphone.name.isEmpty ? String(localized: "Microphone") : devices.microphone.name)
                .truncationMode(.tail)
        } trailing: {
            Text(notice ?? String(localized: "Muted"))
                .foregroundStyle(devices.microphone.muted == true ? .red : .white)
                .truncationMode(.tail)
        }
    }
}

struct DeviceControlsSettings: View {
    var body: some View {
        Section {
            Defaults.Toggle(key: .showPeripheralBatteries) { Text("Show keyboard and headphone batteries") }
            Defaults.Toggle(key: .showMicrophoneButton) { Text("Show microphone button") }
            KeyboardShortcuts.Recorder("Mute microphone:", name: .toggleMicrophoneMute)
            Text("Controls the default system input. Apps using another microphone have their own mute state.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Devices & Microphone")
        }
    }
}
