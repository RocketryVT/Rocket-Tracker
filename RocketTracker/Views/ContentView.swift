//
//  ContentView.swift
//  RocketryAtVT
//
//  Created by Gregory Wainer on 2/4/25.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var presenter: MainPresenter
    @State private var showDeviceSelector: Bool = false

    init() {
        // Create the service and presenter
        let service = BluetoothService()
        _presenter = StateObject(wrappedValue: MainPresenter(bluetoothService: service))
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            // iOS 16+ implementation using NavigationStack
            NavigationStack {
                contentView
            }
        } else {
            // iOS 15 implementation using NavigationView
            NavigationView {
                contentView
            }
            .navigationViewStyle(.stack)
        }
    }

    private var contentView: some View {
    VStack(spacing: 0) {
        // Header with connection status
        connectionHeader
        
        // Map view showing location (conditional)
        if let telemetry = presenter.telemetryData {
            mapView(for: telemetry, presenter: presenter)
            
            if presenter.headingToRocket != nil {
                CompassView(
                    headingToRocket: presenter.headingToRocket,
                    deviceHeading: presenter.deviceHeading,
                    relativeHeadingToRocket: presenter.relativeHeadingToRocket,
                    distance: calculateDistance(
                        from: presenter.userLocation,
                        to: CLLocationCoordinate2D(latitude: telemetry.lat, longitude: telemetry.lon)
                    )
                )
                .padding(8)
            }
        } else {
            // Placeholder when no telemetry data
            VStack {
                Text("No telemetry data available")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding()
                
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                    .padding()
                
                Text("Connect to your rocket to view real-time data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        
        TelemetryDataView(presenter: presenter)
    }
    .navigationTitle("Rocket Tracker")
    .toolbar {
        ToolbarItem(placement: .automatic) {
            Button(action: { showDeviceSelector = true }) {
                Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
        
        ToolbarItem(placement: .automatic) {
            if presenter.isConnected {
                Button(action: { presenter.disconnect() }) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            }
        }
    }
    .sheet(isPresented: $showDeviceSelector) {
        DeviceSelectorView(
            presenter: presenter,
            isPresented: $showDeviceSelector
        )
    }
}
    
    // Connection status header
    private var connectionHeader: some View {
        HStack {
            Image(systemName: presenter.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(presenter.isConnected ? .green : .red)
            
            Text(presenter.isConnected ? "Connected to RocketryAtVT Tracker" : "Not Connected")
                .font(.headline)
            
            Spacer()
            
            if presenter.isConnected, presenter.isSending {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding(.trailing)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.0))
    }
}


func calculateDistance(from userLocation: CLLocationCoordinate2D?, to rocketLocation: CLLocationCoordinate2D) -> Double? {
    guard let userLocation = userLocation else { return nil }
    
    let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
    let rocketCLLocation = CLLocation(latitude: rocketLocation.latitude, longitude: rocketLocation.longitude)
    
    return userCLLocation.distance(from: rocketCLLocation) // Returns distance in meters
}

#Preview {
    ContentView()
}
