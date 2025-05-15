import Foundation
import Combine
import CoreBluetooth
import CoreLocation
import MapKit
import CoreData

class MainPresenter: NSObject, ObservableObject {
    // Published properties for the view
    @Published var isConnected = false
    @Published var telemetryData: TelemetryData?
    @Published var receivedMessages: [ReceivedMessage] = []
    @Published var isSending = false
    @Published var pathCoordinates: [CLLocationCoordinate2D] = []
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.0, longitude: -80.0),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    private let locationManager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var headingToRocket: Double?
    @Published var deviceHeading: Double = 0
    @Published var relativeHeadingToRocket: Double?
    
    // Services
    private let bluetoothService: BluetoothServiceProtocol
    private let dataManager = TelemetryDataManager()
    private var cancellables = Set<AnyCancellable>()
    
    init(bluetoothService: BluetoothServiceProtocol) {
        self.bluetoothService = bluetoothService

        super.init()
        
        dataManager.verifyDataStore()

        // Setup location services
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        setupBindings()
    }

    // Calculate bearing from user to rocket
    func updateHeadingToRocket() {
        guard let userLocation = userLocation,
              let telemetry = telemetryData else {
            headingToRocket = nil
            relativeHeadingToRocket = nil
            return
        }
        
        let rocketLocation = CLLocationCoordinate2D(
            latitude: telemetry.lat,
            longitude: telemetry.lon
        )
        
        // Calculate bearing between points
        let lat1 = userLocation.latitude.toRadians()
        let lon1 = userLocation.longitude.toRadians()
        let lat2 = rocketLocation.latitude.toRadians()
        let lon2 = rocketLocation.longitude.toRadians()
        
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x)
        
        // Absolute bearing (0° = North)
        headingToRocket = (bearing.toDegrees() + 360).truncatingRemainder(dividingBy: 360)
        
        // Calculate relative bearing (rocket position relative to device heading)
        calculateRelativeHeading()
    }

    func calculateRelativeHeading() {
        guard let headingToRocket = headingToRocket else {
            relativeHeadingToRocket = nil
            return
        }
        
        // Calculate the difference between the device heading and direction to rocket
        // This gives us where the rocket is relative to where the device is pointing
        var relativeBearing = headingToRocket - deviceHeading
        
        // Normalize to 0-360 range
        while relativeBearing < 0 {
            relativeBearing += 360
        }
        relativeBearing = relativeBearing.truncatingRemainder(dividingBy: 360)
        
        relativeHeadingToRocket = relativeBearing
    }
    
    private func setupBindings() {
        // Subscribe to service publishers
        bluetoothService.connectionStatusPublisher
            .assign(to: &$isConnected)
        
        bluetoothService.telemetryPublisher
            .sink { [weak self] telemetry in
                self?.telemetryData = telemetry
                
                // Update map coordinates if telemetry has valid location
                if let telemetry = telemetry {

                    self?.dataManager.logTelemetry(telemetry)

                    let coordinate = CLLocationCoordinate2D(
                        latitude: telemetry.lat,
                        longitude: telemetry.lon
                    )
                    
                    if !(self?.pathCoordinates.contains(where: { 
                        $0.latitude == coordinate.latitude && $0.longitude == coordinate.longitude 
                    }) ?? false) {
                        self?.pathCoordinates.append(coordinate)
                        self?.mapRegion.center = coordinate
                    }
                }
            }
            .store(in: &cancellables)
        
        bluetoothService.messagesPublisher
            .assign(to: &$receivedMessages)
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


extension MainPresenter: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last?.coordinate {
            userLocation = location
            updateHeadingToRocket()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Get magnetic heading (direction device is pointing)
        deviceHeading = newHeading.magneticHeading
        
        // Recalculate the relative bearing
        calculateRelativeHeading()
    }
}

extension Double {
    func toRadians() -> Double {
        return self * .pi / 180
    }
    
    func toDegrees() -> Double {
        return self * 180 / .pi
    }
}