import Foundation
import CoreBluetooth
internal import Combine
import MapKit

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isConnected = false
    @Published var statusText = "Initializing... ⏳"

    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    private var lastPayload: Data?
    private var lastWriteAt = Date.distantPast
    private let minWriteInterval: TimeInterval = 0.25

    let serviceUUID = CBUUID(string: "4FAFc201-1FB5-459E-8FCC-C5C9C331914B")
    let characteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            let connectedDevices = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])

            if let alreadyConnectedDevice = connectedDevices.first {
                print("Found ESP32 already connected to the system!")
                esp32Peripheral = alreadyConnectedDevice
                esp32Peripheral?.delegate = self
                centralManager.connect(alreadyConnectedDevice, options: nil)
            } else {
                print("Bluetooth is On. Scanning for ESP32...")
                DispatchQueue.main.async { self.statusText = "Scanning for ESP32... 🔴" }
                centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
            }
        } else {
            print("Bluetooth is not available.")
            DispatchQueue.main.async {
                self.isConnected = false
                self.statusText = "Bluetooth is Turned Off ⚠️"
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        print("Found ESP32!")
        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to ESP32!")
        DispatchQueue.main.async { self.statusText = "ESP32 Connected 🟢" }
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from ESP32!")

        writeCharacteristic = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.statusText = "Disconnected. Scanning... 🔴"
        }

        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                writeCharacteristic = characteristic
                DispatchQueue.main.async {
                    self.isConnected = true
                }
                print("Ready to send commands!")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("BLE write failed: \(error.localizedDescription)")
        }
    }

    func sendCommand(_ command: UInt8) {
        guard let peripheral = esp32Peripheral, let characteristic = writeCharacteristic else {
            print("Not connected to ESP32")
            return
        }

        let data = Data([command])
        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse

        if writeType == .withoutResponse, !peripheral.canSendWriteWithoutResponse {
            return
        }

        peripheral.writeValue(data, for: characteristic, type: writeType)
        print("Sent command: \(command)")
    }

    func sendTurnInstruction(for step: MKRoute.Step) {
        let normalizedInstruction = step.instructions.lowercased()

        if normalizedInstruction.contains("left") {
            sendCommand(1)
        } else if normalizedInstruction.contains("right") {
            sendCommand(2)
        }
    }

    func sendNavigationUpdate(direction: UInt8, distance: Int) {
        guard let peripheral = esp32Peripheral, let characteristic = writeCharacteristic else {
            return
        }

        let clampedDistance = UInt16(clamping: distance)
        let bytes: [UInt8] = [
            direction,
            UInt8(clampedDistance >> 8),
            UInt8(clampedDistance & 0xFF)
        ]
        let data = Data(bytes)

        let now = Date()
        guard now.timeIntervalSince(lastWriteAt) >= minWriteInterval else { return }
        guard data != lastPayload else { return }

        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse

        if writeType == .withoutResponse, !peripheral.canSendWriteWithoutResponse {
            return
        }

        lastPayload = data
        lastWriteAt = now
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }
}
