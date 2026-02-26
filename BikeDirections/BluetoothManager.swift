//
//  BluetoothManager.swift
//  BikeDirections
//
//  Created by Mac-aroni on 2/24/26.
//

import Foundation
import CoreBluetooth
internal import Combine

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var isConnected = false
    @Published var statusText = "Initializing... ⏳"
    
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    let serviceUUID = CBUUID(string: "4FAFc201-1FB5-459E-8FCC-C5C9C331914B")
    let characteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // Check if Bluetooth is ON
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            
            // Check for connections before scanning
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
            // Explicitly show when Bluetooth is off
            DispatchQueue.main.async {
                self.isConnected = false
                self.statusText = "Bluetooth is Turned Off ⚠️"
            }
        }
    }
    
    // Found the ESP32 via Scanning
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Found ESP32!")
        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    // Successfully connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to ESP32!")
        DispatchQueue.main.async { self.statusText = "ESP32 Connected 🟢" }
        peripheral.discoverServices([serviceUUID])
    }
    
    // Handle unexpected disconnects
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
    
    // Found the Service
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    // Found the Characteristic (where we send data)
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
    
    // Function to send the actual Left/Right signal
    func sendCommand(_ command: UInt8) {
        guard let peripheral = esp32Peripheral, let characteristic = writeCharacteristic else {
            print("Not connected to ESP32")
            return
        }
        
        let data = Data([command])
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("Sent command: \(command)")
    }
}
