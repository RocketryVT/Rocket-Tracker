import Foundation
import Combine
import CoreBluetooth
import MapKit

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
    
    // Service
    private let bluetoothService: BluetoothServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(bluetoothService: BluetoothServiceProtocol) {
        self.bluetoothService = bluetoothService
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
    }
    
    func getDiscoveredDevices() -> [(peripheral: CBPeripheral, rssi: NSNumber)] {
        // This could come from a published property as well
        return (bluetoothService as? BluetoothService)?.discoveredDevices ?? []
    }
}
