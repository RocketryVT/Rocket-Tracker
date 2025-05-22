//
//  BluetoothService.swift
//  RocketTracker
//
//  Created by Gregory Wainer on 5/14/25.
//

import CoreBluetooth
import Combine
import SwiftProtobuf

protocol BluetoothServiceProtocol {
    var discoveredDevicesPublisher: Published<[(peripheral: CBPeripheral, rssi: NSNumber)]>.Publisher { get }
    var connectionStatusPublisher: Published<Bool>.Publisher { get }
    var telemetryPublisher: Published<TelemetryData?>.Publisher { get }
    var messagesPublisher: Published<[ReceivedMessage]>.Publisher { get }
    
    func startScanning()
    func stopScanning()
    func connect(to peripheral: CBPeripheral)
    func disconnect()
}

class BluetoothService: NSObject, BluetoothServiceProtocol, ObservableObject {
    @Published private(set) var discoveredDevices: [(peripheral: CBPeripheral, rssi: NSNumber)] = []
    @Published private(set) var isConnected = false
    @Published private(set) var latestTelemetry: TelemetryData?
    @Published private(set) var receivedMessages: [ReceivedMessage] = []
    @Published var isSending = false
    
    var discoveredDevicesPublisher: Published<[(peripheral: CBPeripheral, rssi: NSNumber)]>.Publisher { $discoveredDevices }
    var connectionStatusPublisher: Published<Bool>.Publisher { $isConnected }
    var telemetryPublisher: Published<TelemetryData?>.Publisher { $latestTelemetry }
    var messagesPublisher: Published<[ReceivedMessage]>.Publisher { $receivedMessages }
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var connectedDevice: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    
    // UUIDs
//    private let serviceUUID = CBUUID(string: "10000000-0000-0000-0000-000000000000")
    private let dataCharUUID = CBUUID(string: "00000000-0000-0000-0000-000000000001")
    private let serviceUUID = CBUUID(string: "0000FB34-9B5F-8000-0080-001000003412")
//    private let dataCharUUID = CBUUID(string: "0000FB34-9B5F-8000-0080-001001003412")
    
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

extension BluetoothService: CBCentralManagerDelegate {
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
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothService: CBPeripheralDelegate {
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
        
        print("📲 RAW DATA [\(characteristic.uuid.uuidString)]:")
        print("  Bytes: \(byteArray)")
        print("  Length: \(data.count) bytes")
        
        // Process data based on characteristic UUID
        if characteristic.uuid.uuidString == dataCharUUID.uuidString {
            processTelemetryData(data)
        }
    }
    
    // MARK: - Helper Methods
    
    private func processTelemetryData(_ data: Data) {
        // Try parsing as protobuf first
        do {
            
            let telemetry = try parseProtobufWithLengthPrefix(data: data)
            
            print("Protobuf parsing successful")
            
            // Convert the protobuf model to your app's data model
            let appTelemetry = TelemetryData(
                deviceID: UInt32(telemetry.deviceID),
                time_since_boot: Int(telemetry.timeSinceBoot),
                msg_num: Int(telemetry.msgNum),
                lat: telemetry.lat,
                lon: telemetry.lon,
                alt: telemetry.alt,
                num_sats: Int(telemetry.numSats),
                gps_fix: gpsFix(from: telemetry.gpsFix),
                gps_time: UTCTime(
                    itow: Int(telemetry.gpsTime.itow),
                    time_accuracy_estimate_ns: Int(telemetry.gpsTime.timeAccuracyEstimateNs),
                    year: Int(telemetry.gpsTime.year),
                    month: Int(telemetry.gpsTime.month),
                    day: Int(telemetry.gpsTime.day),
                    hour: Int(telemetry.gpsTime.hour),
                    min: Int(telemetry.gpsTime.min),
                    sec: Int(telemetry.gpsTime.sec),
                    nanos: Int(telemetry.gpsTime.nanos),
                    valid: Int(telemetry.gpsTime.valid)
                ),
                baro_alt: Double(telemetry.baroAlt)
            )
            
            DispatchQueue.main.async {
                self.latestTelemetry = appTelemetry
                
                // Add simple formatted message
                let message = "Time: \(appTelemetry.time_since_boot), Lat: \(appTelemetry.lat), Lon: \(appTelemetry.lon)"
                self.addMessage(message)
            }
            return
        } catch {
            // Not protobuf or error parsing, try JSON instead
            print("Not a valid protobuf: \(error). Falling back to JSON")
        }
    }

    enum CustomError: Error {
        case invalidLength
        case invalidData
        case parsingFailure
    }
    
    private func parseProtobufWithLengthPrefix(data: Data) throws -> RKTMiniData {
        guard data.count >= 2 else {
            throw CustomError.invalidLength
        }
        
        // Extract length (first two bytes, little endian)
        let length = UInt16(data[0]) + (UInt16(data[1]) << 8)
        print("Parsed length: \(length)")
        
        // Ensure length is valid
        guard length > 0, length <= data.count - 2 else {
            throw CustomError.invalidLength
        }
        
        // Extract actual protobuf data using the length
        let protobufData = data.subdata(in: 2..<(Int(length) + 2))
        print("Extracted protobuf data: \(protobufData)")
        
        // Parse the protobuf data
        return try RKTMiniData(serializedBytes: protobufData)
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

// Helper function to convert RKTGpsFix enum to a String
private func gpsFix(from fix: RKTGpsFix) -> String {
    switch fix {
    case .noFix:
        return "No Fix"
    case .deadReckoningOnly:
        return "Dead Reckoning Only"
    case .fix2D:
        return "2D Fix"
    case .fix3D:
        return "3D Fix"
    case .gpsPlusDeadReckoning:
        return "GPS + Dead Reckoning"
    case .timeOnlyFix:
        return "Time Only Fix"
    case .UNRECOGNIZED(let value):
        return "Unknown (\(value))"
    }
}
