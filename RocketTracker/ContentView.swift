//
//  ContentView.swift
//  RocketryAtVT
//
//  Created by Gregory Wainer on 2/4/25.
//

import SwiftUI
import MapKit
//#if os(macOS)
//import AppKit
//#endif

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var showDeviceSelector = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.0, longitude: -80.0), // Default to Blacksburg, VA
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var pathCoordinates: [CLLocationCoordinate2D] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with connection status
                connectionHeader
                
                // Map view showing location
                if bluetoothManager.isConnected, let telemetry = bluetoothManager.latestTelemetry {
                    mapView(for: telemetry)
                } else {
                    placeholderMapView
                }
                
                // Telemetry data display
                telemetryDataView
            }
            .navigationTitle("Rocket Tracker")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showDeviceSelector = true }) {
                        Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if bluetoothManager.isConnected {
                        Button(action: { bluetoothManager.disconnect() }) {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button(action: { showDeviceSelector = true }) {
                        Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    if bluetoothManager.isConnected {
                        Button(action: { bluetoothManager.disconnect() }) {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    }
                }
                #endif
            }
            .sheet(isPresented: $showDeviceSelector) {
                DeviceSelectorView(bluetoothManager: bluetoothManager, isPresented: $showDeviceSelector)
            }
        }
    }
    
    // Connection status header
    private var connectionHeader: some View {
        HStack {
            Image(systemName: bluetoothManager.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(bluetoothManager.isConnected ? .green : .red)
            
            Text(bluetoothManager.isConnected ? "Connected to RocketryAtVT Tracker" : "Not Connected")
                .font(.headline)
            
            Spacer()
            
            if bluetoothManager.isConnected, bluetoothManager.isSending {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding(.trailing)
            }
        }
        .padding()
        // .background(Color(UIColor.secondarySystemBackground))
        // .background(.regularMaterial)
        .background(Color.secondary.opacity(0.0))
    }
    
    // Map view with location tracking
    private func mapView(for telemetry: TelemetryData) -> some View {
        let coordinate = CLLocationCoordinate2D(
            latitude: telemetry.lat,
            longitude: telemetry.lon
        )
        
        // Update breadcrumb trail
        if !pathCoordinates.contains(where: { $0.latitude == coordinate.latitude && $0.longitude == coordinate.longitude }) {
            DispatchQueue.main.async {
                pathCoordinates.append(coordinate)
                mapRegion.center = coordinate
            }
        }
        
        return Map(initialPosition: MapCameraPosition.region(mapRegion)) {
            // Add marker for current position
            Marker("Rocket", coordinate: coordinate)
                .tint(.red)
            
            // Add path for breadcrumb trail
            if pathCoordinates.count > 1 {
                MapPolyline(coordinates: pathCoordinates)
                    .stroke(.blue, lineWidth: 3)
            }
        }
        .frame(height: 300)
    }
    
    // Placeholder map when not connected
    private var placeholderMapView: some View {
        ZStack {
            // Color(UIColor.secondarySystemBackground)
            Color(Color.secondary.opacity(0.1))
            VStack {
                Image(systemName: "map")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                Text("Connect to Rocket Tracker to view location")
                    .foregroundColor(.gray)
            }
        }
        .frame(height: 300)
    }
    
    // Telemetry data display
    private var telemetryDataView: some View {
        ScrollView {
            if bluetoothManager.isConnected, let telemetry = bluetoothManager.latestTelemetry {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox(label: Label("GPS Data", systemImage: "location.fill")) {
                        VStack(alignment: .leading, spacing: 4) {
                            DataRow(label: "Latitude", value: String(format: "%.6f°", telemetry.lat))
                            DataRow(label: "Longitude", value: String(format: "%.6f°", telemetry.lon))
                            DataRow(label: "Altitude", value: String(format: "%.1f m", telemetry.alt))
                            DataRow(label: "Satellites", value: "\(telemetry.num_sats)")
                            DataRow(label: "GPS Fix", value: telemetry.gps_fix)
                            DataRow(label: "Baro Alt", value: String(format: "%.1f m", telemetry.baro_alt))
                        }
                        .padding(.vertical, 6)
                    }
                    
//                    GroupBox(label: Label("IMU Data", systemImage: "gyroscope")) {
//                        VStack(alignment: .leading, spacing: 4) {
//                            Text("Accelerometer (g)")
//                                .font(.subheadline)
//                                .foregroundColor(.secondary)
//                            HStack {
//                                DataColumn(label: "X", value: String(format: "%.2f", telemetry.ism_axel_x))
//                                DataColumn(label: "Y", value: String(format: "%.2f", telemetry.ism_axel_y))
//                                DataColumn(label: "Z", value: String(format: "%.2f", telemetry.ism_axel_z))
//                            }
//
//                            Text("Gyroscope (deg/s)")
//                                .font(.subheadline)
//                                .foregroundColor(.secondary)
//                                .padding(.top, 8)
//                            HStack {
//                                DataColumn(label: "X", value: String(format: "%.2f", telemetry.ism_gyro_x))
//                                DataColumn(label: "Y", value: String(format: "%.2f", telemetry.ism_gyro_y))
//                                DataColumn(label: "Z", value: String(format: "%.2f", telemetry.ism_gyro_z))
//                            }
//                        }
//                        .padding(.vertical, 6)
//                    }
//
                    GroupBox(label: Label("System", systemImage: "clock")) {
                        VStack(alignment: .leading, spacing: 4) {
                            DataRow(label: "Boot Time", value: "\(telemetry.time_since_boot) ms")
                            DataRow(label: "Message #", value: "\(telemetry.msg_num)")
                            DataRow(label: "Date", value: "\(telemetry.gps_time.day)/\(telemetry.gps_time.month)/\(telemetry.gps_time.year)")
                            DataRow(label: "Time", value: String(format: "%02d:%02d:%02d",
                                                                telemetry.gps_time.hour,
                                                                telemetry.gps_time.min,
                                                                telemetry.gps_time.sec))
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "waveform.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No data available")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Connect to Rocket Tracker to view telemetry data")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
}

// Helper Components
struct DataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct DataColumn: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MapPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    ContentView()
}
