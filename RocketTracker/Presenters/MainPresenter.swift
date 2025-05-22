import Foundation
import Combine
import CoreBluetooth
import MapKit
import CoreData

class MainPresenter: NSObject, ObservableObject {
    // Published properties for the view
    @Published var isConnected = false
    @Published var telemetryDataByDevice: [UInt32: TelemetryData] = [:]
    @Published var receivedMessages: [ReceivedMessage] = []
    @Published var isSending = false
    @Published var pathCoordinatesByDevice: [UInt32: [CLLocationCoordinate2D]] = [:]
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.0, longitude: -80.0),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var selectedDeviceID: UInt32? = nil // Track which device is selected
    
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var headingToRocket: Double?
    @Published var deviceHeading: Double = 0
    @Published var relativeHeadingToRocket: Double?

    var telemetryData: TelemetryData? {
        if let selected = selectedDeviceID {
            return telemetryDataByDevice[selected]
        }
        return telemetryDataByDevice.values.first
    }

    var pathCoordinates: [CLLocationCoordinate2D] {
        if let selected = selectedDeviceID {
            return pathCoordinatesByDevice[selected] ?? []
        }
        return pathCoordinatesByDevice.values.first ?? []
    }
    
    // Services
    private let bluetoothService: BluetoothServiceProtocol
    private let locationService: LocationServiceProtocol
    private let dataManager = TelemetryDataManager()
    private var cancellables = Set<AnyCancellable>()
    
    init(bluetoothService: BluetoothServiceProtocol, locationService: LocationServiceProtocol) {
        self.bluetoothService = bluetoothService
        self.locationService = locationService

        super.init()
        
        dataManager.verifyDataStore()

        setupBindings()
    }

    // Calculate bearing from user to rocket
    func updateHeadingToSelectedDevice() {
        if let selected = selectedDeviceID {
            updateHeadingToDevice(deviceID: selected)
            
            // Update the published properties
            headingToRocket = deviceHeadings[selected]
            relativeHeadingToRocket = relativeDeviceHeadings[selected]
        } else if let firstDevice = telemetryDataByDevice.keys.first {
            updateHeadingToDevice(deviceID: firstDevice)
            
            // Update the published properties
            headingToRocket = deviceHeadings[firstDevice]
            relativeHeadingToRocket = relativeDeviceHeadings[firstDevice]
        } else {
            headingToRocket = nil
            relativeHeadingToRocket = nil
        }
    }

    // Calculate relative heading for specific device
    func calculateRelativeHeading(for deviceID: UInt32) {
        guard let heading = deviceHeadings[deviceID] else {
            relativeDeviceHeadings[deviceID] = nil
            return
        }
        
        // Calculate the difference between the device heading and direction to rocket
        var relativeBearing = heading - deviceHeading
        
        // Normalize to 0-360 range
        while relativeBearing < 0 {
            relativeBearing += 360
        }
        relativeBearing = relativeBearing.truncatingRemainder(dividingBy: 360)
        
        relativeDeviceHeadings[deviceID] = relativeBearing
    }
    
    // Get telemetry records for specific device
    func getTelemetryRecords(deviceID: UInt32? = nil, from startDate: Date? = nil, to endDate: Date? = nil) -> [NSManagedObject] {
        return dataManager.getTelemetryRecords(deviceID: deviceID, from: startDate, to: endDate)
    }
    
    // Get available dates for specific device
    func getAvailableDates(forDeviceID deviceID: UInt32? = nil) -> [Date] {
        return dataManager.getAvailableDates(forDeviceID: deviceID)
    }
    
    // Delete records for specific device and date
    func deleteRecordsForDate(_ date: Date, deviceID: UInt32? = nil) {
        dataManager.deleteRecordsForDate(date, deviceID: deviceID)
    }
    
    private func setupBindings() {
        // Subscribe to service publishers
        bluetoothService.connectionStatusPublisher
            .assign(to: &$isConnected)
        
        bluetoothService.telemetryPublisher
            .sink { [weak self] telemetry in
                guard let self = self, let data = telemetry else { return }
                
                // Store data for this device
                self.telemetryDataByDevice[data.deviceID] = telemetry
                
                // Log the telemetry data
                self.dataManager.logTelemetry(data)
                
                // If this is a new device, select it
                if self.selectedDeviceID == nil {
                    self.selectedDeviceID = data.deviceID
                }
                
                // Update path coordinates for this device
                let coordinate = CLLocationCoordinate2D(
                    latitude: data.lat,
                    longitude: data.lon
                )
                
                if self.pathCoordinatesByDevice[data.deviceID] == nil {
                    self.pathCoordinatesByDevice[data.deviceID] = []
                }
                
                // Add the coordinate to the path
                self.pathCoordinatesByDevice[data.deviceID]?.append(coordinate)
                
                // Limit path length to prevent memory issues
                if let pathCount = self.pathCoordinatesByDevice[data.deviceID]?.count,
                pathCount > 1000 {
                    self.pathCoordinatesByDevice[data.deviceID]?.removeFirst()
                }
                
                // Update headings
                self.updateHeadingsForAllDevices()
                
                // Center map on selected device
                if let selectedID = self.selectedDeviceID,
                let selectedTelemetry = self.telemetryDataByDevice[selectedID] {
                    self.mapRegion.center = CLLocationCoordinate2D(
                        latitude: selectedTelemetry.lat,
                        longitude: selectedTelemetry.lon
                    )
                }
            }
            .store(in: &cancellables)
        
        bluetoothService.messagesPublisher
            .assign(to: &$receivedMessages)
    }

    // Select a specific device to focus on
    func selectDevice(_ deviceID: UInt32?) {
        self.selectedDeviceID = deviceID
        
        // Update map region if we have data for this device
        if let deviceID = deviceID, 
        let telemetry = telemetryDataByDevice[deviceID] {
            mapRegion.center = CLLocationCoordinate2D(
                latitude: telemetry.lat,
                longitude: telemetry.lon
            )
        }
        
        // Update headings
        updateHeadingsForAllDevices()
        
        // Update published properties to reflect selected device
        if let deviceID = selectedDeviceID {
            headingToRocket = deviceHeadings[deviceID]
            relativeHeadingToRocket = relativeDeviceHeadings[deviceID]
        } else {
            headingToRocket = deviceHeadings.values.first
            relativeHeadingToRocket = relativeDeviceHeadings.values.first
        }
    }

    // Get all device IDs with telemetry data
    func getAvailableDeviceIDs() -> [UInt32] {
        // Combine current devices and historical devices
        var deviceIDs = Array(telemetryDataByDevice.keys)
        
        // Add historical devices from database
        let historicalDeviceIDs = dataManager.getAllDeviceIDs()
        for deviceID in historicalDeviceIDs {
            if !deviceIDs.contains(deviceID) {
                deviceIDs.append(deviceID)
            }
        }
        
        return deviceIDs.sorted()
    }

    func getAllDeviceIDs() -> [UInt32] {
        return dataManager.getAllDeviceIDs()
    }

    // Access methods for telemetry by device
    func getTelemetryData(for deviceID: UInt32) -> TelemetryData? {
        return telemetryDataByDevice[deviceID]
    }

    func getPathCoordinates(for deviceID: UInt32) -> [CLLocationCoordinate2D] {
        return pathCoordinatesByDevice[deviceID] ?? []
    }

    // Calculate bearings for all devices
    private func updateHeadingsForAllDevices() {
        // Update for each device
        for (deviceID, _) in telemetryDataByDevice {
            updateHeadingToDevice(deviceID: deviceID)
        }
    }

        // Calculate bearing to a specific device
    func updateHeadingToDevice(deviceID: UInt32) {
        guard let userLocation = userLocation,
              let telemetry = telemetryDataByDevice[deviceID] else {
            return
        }
        
        let deviceLocation = CLLocationCoordinate2D(
            latitude: telemetry.lat,
            longitude: telemetry.lon
        )
        
        // Calculate bearing between points
        let lat1 = userLocation.latitude.toRadians()
        let lon1 = userLocation.longitude.toRadians()
        let lat2 = deviceLocation.latitude.toRadians()
        let lon2 = deviceLocation.longitude.toRadians()
        
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x)
        
        // Store heading for this device
        let headingDegrees = (bearing.toDegrees() + 360).truncatingRemainder(dividingBy: 360)
        deviceHeadings[deviceID] = headingDegrees
        
        // Calculate relative bearing
        calculateRelativeHeading(for: selectedDeviceID ?? telemetryDataByDevice.keys.first!)
    }

    // Maps to store headings for each device
    var deviceHeadings: [UInt32: Double] = [:]
    var relativeDeviceHeadings: [UInt32: Double] = [:]
    
    // Compatibility properties for single device mode
    var selectedDeviceHeading: Double? {
        if let selected = selectedDeviceID {
            return deviceHeadings[selected]
        }
        return deviceHeadings.values.first
    }
    
    var selectedDeviceRelativeHeading: Double? {
        if let selected = selectedDeviceID {
            return relativeDeviceHeadings[selected]
        }
        return relativeDeviceHeadings.values.first
    }
    
    // Public methods for the view
    func startScanning() {
        bluetoothService.startScanning()
    }
    
    func stopScanning() {
        bluetoothService.stopScanning()
    }
    
    func connect(to peripheral: CBPeripheral) {
        bluetoothService.connect(to: peripheral)
    }
    
    func disconnect() {
        bluetoothService.disconnect()
        // Force any pending saves
        self.dataManager.forceSave()
    }
    
    func getDiscoveredDevices() -> [(peripheral: CBPeripheral, rssi: NSNumber)] {
        // This could come from a published property as well
        return (bluetoothService as? BluetoothService)?.discoveredDevices ?? []
    }

    func getTelemetryRecords(from startDate: Date? = nil, to endDate: Date? = nil) -> [NSManagedObject] {
        let records = dataManager.getTelemetryRecords(from: startDate, to: endDate)
        print("Retrieved \(records.count) records for date range")
        return records
    }

    func getAvailableDates() -> [Date] {
        let dates = dataManager.getAvailableDates()
        print("Retrieved \(dates.count) available dates")
        return dates
    }

    func deleteOldRecords(olderThan date: Date) {
        dataManager.deleteRecords(olderThan: date)
    }

    func deleteRecordsForDate(_ date: Date) {
        print("MainPresenter: Deleting records for \(date)")
        dataManager.deleteRecordsForDate(date)
    }
}


//extension MainPresenter: CLLocationManagerDelegate {
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        updateHeadingToSelectedDevice()
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
//        // Recalculate the relative bearing
//        updateHeadingToSelectedDevice()
//    }
//}

extension Double {
    func toRadians() -> Double {
        return self * .pi / 180
    }
    
    func toDegrees() -> Double {
        return self * 180 / .pi
    }
}