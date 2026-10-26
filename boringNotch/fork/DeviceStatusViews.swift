import Defaults
import KeyboardShortcuts
import SwiftUI

struct DeviceHeaderControls: View {
    @ObservedObject private var devices = DeviceStatusManager.shared
    @Default(.showPeripheralBatteries) private var showBatteries
    @Default(.showMicrophoneButton) private var showMicrophone
    @State private var showDetails = false

    var body: some View {
        HStack(spacing: 6) {
            if showBatteries {
                Button { showDetails.toggle() } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(devices.peripherals.prefix(2))) { device in
                                batteryLabel(device)
                            }
                            if devices.peripherals.isEmpty { Image(systemName: "keyboard") }
                        }
                        .fixedSize()
                        VStack(spacing: 1) {
                            ForEach(Array(devices.peripherals.prefix(2))) { device in
                                batteryLabel(device)
                            }
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .fixedSize()
                        HStack(spacing: 3) {
                            ForEach(Array(devices.peripherals.prefix(2))) { device in
                                Image(systemName: device.symbol)
                            }
                            if devices.peripherals.isEmpty { Image(systemName: "keyboard") }
                        }
                        .fixedSize()
                    }
                    .frame(minWidth: 22, maxWidth: 108)
                    .frame(height: 28)
                }
                .buttonStyle(.plain)
                .help("Bluetooth device batteries")
                .popover(isPresented: $showDetails) { batteryDetails }
                .onAppear { devices.startWatchingBatteries() }
                .onDisappear { devices.stopWatchingBatteries() }
            }
            if showMicrophone {
                Button { devices.toggleMicrophone() } label: {
                    Image(systemName: devices.microphone.error != nil ? "mic.badge.xmark" : devices.microphone.muted == true ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(devices.microphone.error != nil ? .yellow : devices.microphone.muted == true ? .red : .white)
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(devices.isToggling)
                .help(microphoneHelp)
                .accessibilityLabel(devices.microphone.muted == true ? Text("Unmute microphone") : Text("Mute microphone"))
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
    }

    private var microphoneHelp: String {
        if devices.microphone.error != nil { return devices.microphoneError }
        let action = devices.microphone.muted == true ? String(localized: "Unmute microphone") : String(localized: "Mute microphone")
        return devices.microphone.name.isEmpty ? action : "\(action) · \(devices.microphone.name)"
    }

    private func batteryLabel(_ device: PeripheralBattery) -> some View {
        HStack(spacing: 3) {
            Image(systemName: device.symbol)
            Text(device.percent.map { "\($0)%" } ?? "—")
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
                            ForEach(["main", "left", "right", "case"], id: \.self) { part in
                                if let level = device.levels[part] {
                                    HStack {
                                        Text(partLabel(part))
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

    private func partLabel(_ part: String) -> String {
        switch part {
        case "left": return String(localized: "Left earbud")
        case "right": return String(localized: "Right earbud")
        case "case": return String(localized: "Charging case")
        default: return String(localized: "Battery")
        }
    }
}

struct MicrophoneClosedIndicator: View {
    @ObservedObject private var devices = DeviceStatusManager.shared

    var body: some View {
        if devices.microphone.muted == true || devices.microphoneNotice != nil {
            HStack(spacing: 6) {
                Image(systemName: devices.microphone.muted == true ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(devices.microphone.muted == true ? .red : .white)
                if let notice = devices.microphoneNotice { Text(notice).font(.caption) }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black, in: Capsule())
            .help(devices.microphone.name)
            .allowsHitTesting(false)
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
