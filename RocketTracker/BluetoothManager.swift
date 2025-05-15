//
//  BluetoothManager.swift
//  RocketTracker
//
//  Created by Gregory Wainer on 3/8/25.
//

import CoreBluetooth
import Combine
import Foundation

import Serde

struct TelemetryData: Codable {
    let time_since_boot: Int
    let msg_num: Int
    let lat: Double
    let lon: Double
    let alt: Double
    let num_sats: Int
    let gps_fix: String
    let gps_time: UTCTime
    let baro_alt: Double
}

//struct TelemetryData: Codable {
//    let time_since_boot: Int
//    let msg_num: Int
//    let lat: Double
//    let lon: Double
//    let alt: Double
//    let num_sats: Int
//    let gps_fix: String
//    let gps_time: UTCTime
//    let baro_alt: Double
//    let ism_axel_x: Double
//    let ism_axel_y: Double
//    let ism_axel_z: Double
//    let ism_gyro_x: Double
//    let ism_gyro_y: Double
//    let ism_gyro_z: Double
//    let lsm_axel_x: Double
//    let lsm_axel_y: Double
//    let lsm_axel_z: Double
//    let lsm_gyro_x: Double
//    let lsm_gyro_y: Double
//    let lsm_gyro_z: Double
//    let adxl_axel_x: Double
//    let adxl_axel_y: Double
//    let adxl_axel_z: Double
//    let ism_axel_x2: Double
//    let ism_axel_y2: Double
//    let ism_axel_z2: Double
//    let ism_gyro_x2: Double
//    let ism_gyro_y2: Double
//    let ism_gyro_z2: Double
//}

struct UTCTime: Codable {
    let itow: Int
    let time_accuracy_estimate_ns: Int
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let min: Int
    let sec: Int
    let nanos: Int
    let valid: Int
}

class BluetoothManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var discoveredDevices: [(peripheral: CBPeripheral, rssi: NSNumber)] = []
    @Published var isConnected = false
    @Published var latestTelemetry: TelemetryData? // Holds the latest telemetry data received
    @Published var receivedMessages: [ReceivedMessage] = []
    @Published var isSending = false
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var connectedDevice: CBPeripheral?
    private var telemetryCharacteristic: CBCharacteristic?
    private var dataCharacteristic: CBCharacteristic?
    
    // Important UUIDs - Updated to match Rust code
    private let serviceUUID = CBUUID(string: "0000FB34-9B5F-8000-0080-001000003412")
    private let dataCharUUID = CBUUID(string: "0000FB34-9B5F-8000-0080-001001003412")
    
    // MARK: - Models
    struct ReceivedMessage: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let message: String
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: ReceivedMessage, rhs: ReceivedMessage) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    /// Start scanning for Bluetooth devices
    func startScanning() {
        if centralManager.state == .poweredOn {
            discoveredDevices = []
            centralManager.scanForPeripherals(withServices: nil, options: nil)
            print("Started scanning for devices")
        } else {
            print("Bluetooth is not powered on")
        }
    }
    
    /// Stop scanning for Bluetooth devices
    func stopScanning() {
        centralManager.stopScan()
        print("Stopped scanning for devices")
    }
    
    /// Connect to a discovered peripheral
    func connect(to peripheral: CBPeripheral) {
        print("Connecting to \(peripheral.name ?? "Unknown Device")...")
        centralManager.connect(peripheral, options: nil)
    }
    
    /// Disconnect from the connected peripheral
    func disconnect() {
        if let peripheral = connectedDevice {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            startScanning()
        case .poweredOff:
            print("Bluetooth is powered off")
            isConnected = false
        case .unsupported:
            print("Bluetooth is not supported on this device")
        case .unauthorized:
            print("Bluetooth use is not authorized")
        case .resetting:
            print("Bluetooth is resetting")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Only add devices with names to our list
        if let name = peripheral.name, !name.isEmpty {
            if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                discoveredDevices.append((peripheral, RSSI))
            } else if let index = discoveredDevices.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier }) {
                discoveredDevices[index].rssi = RSSI
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDevice = peripheral
        peripheral.delegate = self
        print("Connected to \(peripheral.name ?? "Unknown Device")")
        
        // Discover services after a brief delay to let connection stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            peripheral.discoverServices(nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown Device")")
        connectedDevice = nil
        dataCharacteristic = nil
        telemetryCharacteristic = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("Found characteristic: \(characteristic.uuid)")
            
            // Look for our data characteristic
            if characteristic.uuid.uuidString == dataCharUUID.uuidString {
                print("Found data characteristic")
                dataCharacteristic = characteristic
                
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    print("Enabled notifications for data characteristic")
                }
                
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
        
        // If we found our data characteristic, we're connected
        if dataCharacteristic != nil {
            DispatchQueue.main.async {
                self.isConnected = true
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error reading characteristic: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else { return }

        // Enhanced debug logging
        let byteArray = [UInt8](data)
        let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        
        print("📲 RAW DATA [\(characteristic.uuid.uuidString)]:")
        print("  Bytes: \(byteArray)")
        print("  Hex: \(hexString)")
        print("  UTF8: \(String(data: data, encoding: .utf8) ?? "Not valid UTF8")")
        print("  Length: \(data.count) bytes")
        
        // Process data based on characteristic UUID
        if characteristic.uuid.uuidString == dataCharUUID.uuidString {
            processTelemetryData(data)
        }
    }
    
    // MARK: - Helper Methods
    
    private func processTelemetryData(_ data: Data) {
        do {
            // Convert data to string, trim null terminators
            if let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) {
                let jsonData = jsonString.data(using: .utf8)!
                let telemetry = try JSONDecoder().decode(TelemetryData.self, from: jsonData)
                
                DispatchQueue.main.async {
                    self.latestTelemetry = telemetry
                    
                    // Add simple formatted message
                    let message = "Time: \(telemetry.time_since_boot), Lat: \(telemetry.lat), Lon: \(telemetry.lon)"
                    self.addMessage(message)
                }
            }
        } catch {
            print("Error parsing telemetry: \(error)")
        }
    }
    
    private func addMessage(_ message: String) {
        DispatchQueue.main.async {
            self.receivedMessages.append(ReceivedMessage(timestamp: Date(), message: message))
            
            // Keep only last 10 messages
            if self.receivedMessages.count > 10 {
                self.receivedMessages.removeFirst()
            }
        }
    }
}
