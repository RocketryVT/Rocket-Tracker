//
//  TelemetryViews.swift
//  RocketTracker
//
//  Created by Gregory Wainer on 5/14/25.
//

import SwiftUI

struct TelemetryDataView: View {
    @ObservedObject var presenter: MainPresenter
    
    var body: some View {
        ScrollView {
            if presenter.isConnected, let telemetry = presenter.telemetryData {
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

#Preview {
    let service = BluetoothService()
    let presenter = MainPresenter(bluetoothService: service)
    return TelemetryDataView(presenter: presenter)
}