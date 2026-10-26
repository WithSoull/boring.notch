//
//  BLEBatteryMonitor.swift
//  boringNotch
//
//  Reads the standard GATT Battery Service of already-connected Bluetooth LE devices.
//  macOS doesn't expose these levels for third-party keyboards (e.g. ZMK split keyboards),
//  and a split keyboard's central half may report the other half as a second Battery Level characteristic.
//

import Combine
import CoreBluetooth

@MainActor
final class BLEBatteryMonitor: NSObject, ObservableObject {
    static let shared = BLEBatteryMonitor()

    /// Battery levels per device name, in characteristic order (the central half first).
    @Published private(set) var levels: [String: [Int]] = [:]

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    /// Characteristic order per peripheral, so repeated reads keep the halves in place.
    private var characteristicOrder: [UUID: [CBCharacteristic]] = [:]
    private var values: [UUID: [ObjectIdentifier: Int]] = [:]

    /// Creating the manager asks for Bluetooth access the first time.
    func refresh() {
        guard let central else {
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        guard central.state == .poweredOn else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) {
            if peripherals[peripheral.identifier] == nil {
                peripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
            }
            if peripheral.state == .connected {
                readBattery(of: peripheral)
            } else {
                central.connect(peripheral)
            }
        }
    }

    private func readBattery(of peripheral: CBPeripheral) {
        let characteristics = characteristicOrder[peripheral.identifier] ?? []
        if characteristics.isEmpty {
            peripheral.discoverServices([Self.batteryService])
        } else {
            characteristics.forEach { peripheral.readValue(for: $0) }
        }
    }

    private func publish(_ peripheral: CBPeripheral) {
        guard let name = peripheral.name, let order = characteristicOrder[peripheral.identifier] else { return }
        let readings = values[peripheral.identifier] ?? [:]
        let list = order.compactMap { readings[ObjectIdentifier($0)] }
        if levels[name] != list { levels[name] = list }
    }
}

extension BLEBatteryMonitor: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn { refresh() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { readBattery(of: peripheral) }
    }
}

extension BLEBatteryMonitor: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for service in peripheral.services ?? [] where service.uuid == Self.batteryService {
                peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            let found = (service.characteristics ?? []).filter { $0.uuid == Self.batteryLevel }
            var order = characteristicOrder[peripheral.identifier] ?? []
            for characteristic in found where !order.contains(where: { $0 === characteristic }) {
                order.append(characteristic)
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            characteristicOrder[peripheral.identifier] = order
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, let byte = characteristic.value?.first, byte <= 100 else { return }
            values[peripheral.identifier, default: [:]][ObjectIdentifier(characteristic)] = Int(byte)
            publish(peripheral)
        }
    }
}
