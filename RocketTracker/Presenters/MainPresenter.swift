import Foundation
import Combine
import CoreBluetooth
import MapKit
import CoreData

class MainPresenter: ObservableObject {
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
    
    // Services
    private let bluetoothService: BluetoothServiceProtocol
    private let dataManager = TelemetryDataManager()
    private var cancellables = Set<AnyCancellable>()
    
    init(bluetoothService: BluetoothServiceProtocol) {
        self.bluetoothService = bluetoothService
        dataManager.verifyDataStore()
        setupBindings()
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
