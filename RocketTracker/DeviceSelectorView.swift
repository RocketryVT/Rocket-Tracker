//
//  DeviceSelectorView.swift
//  RocketryAtVT
//
//  Created by Gregory Wainer on 5/5/25.
//


import SwiftUI
import CoreBluetooth

struct DeviceSelectorView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var isPresented: Bool
    
    // Filter name to only show "RocketryAtVT Tracker" devices
    private let deviceName = "RocketryAtVT Tracker"
    
    var body: some View {
        NavigationStack {
            VStack {
                if filteredDevices.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
            }
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        bluetoothManager.startScanning()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                bluetoothManager.startScanning()
            }
            .onDisappear {
                bluetoothManager.stopScanning()
            }
        }
    }
    
    // Filter devices to only show our target device
    private var filteredDevices: [(peripheral: CBPeripheral, rssi: NSNumber)] {
        return bluetoothManager.discoveredDevices.filter {
            $0.peripheral.name?.contains(deviceName) ?? false
        }
    }
    
    // Empty state when no devices found
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Searching for Rocket Tracker...")
                .font(.headline)
            
            Text("Make sure the tracker is powered on and in range")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            ProgressView()
                .padding()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // List of discovered devices
    private var deviceListView: some View {
        List {
            Section(header: Text("Available Devices")) {
                ForEach(filteredDevices, id: \.peripheral.identifier) { device in
                    Button(action: {
                        connectToDevice(device.peripheral)
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.peripheral.name ?? "Unknown")
                                    .font(.headline)
                                Text(device.peripheral.identifier.uuidString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Signal strength indicator
                            signalStrengthView(rssi: device.rssi.intValue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    // Connect to selected device and close sheet
    private func connectToDevice(_ peripheral: CBPeripheral) {
        bluetoothManager.connect(to: peripheral)
        isPresented = false
    }
    
    // RSSI signal strength indicator
    private func signalStrengthView(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                Rectangle()
                    .fill(signalStrengthColor(for: rssi, bar: index))
                    .frame(width: 4, height: 8 + CGFloat(index) * 4)
            }
        }
    }
    
    // Determine color for signal strength bars
    private func signalStrengthColor(for rssi: Int, bar: Int) -> Color {
        let strength: Int
        
        if rssi >= -60 {
            strength = 4 // Excellent
        } else if rssi >= -70 {
            strength = 3 // Good
        } else if rssi >= -80 {
            strength = 2 // Fair
        } else if rssi >= -90 {
            strength = 1 // Poor
        } else {
            strength = 0 // Very poor
        }
        
        if bar < strength {
            // Create a gradient from red (weak) to green (strong)
            let hue = min(0.4, Double(rssi + 100) / 100.0)
            return Color(hue: hue, saturation: 1.0, brightness: 0.8)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
}

#Preview {
    DeviceSelectorView(bluetoothManager: BluetoothManager(), isPresented: .constant(true))
}
