//
//  TelemetryViews.swift
//  RocketTracker
//
//  Created by Gregory Wainer on 5/14/25.
//

import SwiftUI
import CoreData

struct TelemetryDataView: View {
    @ObservedObject var presenter: MainPresenter
    @State private var showLogsSheet = false
    
    var body: some View {
        ScrollView {
            if presenter.isConnected {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .padding(.trailing, 4)
                    Text("Recording telemetry data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            if let telemetry = presenter.telemetryData {
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
        .navigationTitle("Rocket Telemetry")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showLogsSheet = true
                }) {
                    Label("Logs", systemImage: "list.bullet.clipboard")
                }
            }
        }
        .sheet(isPresented: $showLogsSheet) {
            TelemetryLogBrowser(presenter: presenter)
        }
    }
}

// Update the TelemetryLogBrowser with this improved version:

struct TelemetryLogBrowser: View {
    @ObservedObject var presenter: MainPresenter
    @State private var selectedDate: Date?
    @State private var recordsForDate: [NSManagedObject] = []
    @State private var showingDataDetail = false
    @State private var logDates: [Date] = []
    @State private var isLoading = false
    @State private var showingDeleteAlert = false
    @State private var dateToDelete: Date?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                List {
                    if logDates.isEmpty {
                        Text("No telemetry data recorded")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(logDates, id: \.self) { date in
                            Button(action: {
                                loadRecordsForDate(date)
                            }) {
                                HStack {
                                    Image(systemName: "calendar")
                                    Text(dateFormatter.string(from: date))
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    dateToDelete = date
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                
                if isLoading {
                    ProgressView("Loading records...")
                        .padding()
                        .background(Color(UIColor.systemBackground).opacity(0.8))
                        .cornerRadius(8)
                }
            }
            .navigationTitle("Telemetry History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        refreshLogDates()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingDataDetail) {
                if let date = selectedDate {
                    TelemetryLogDetailView(date: date, records: recordsForDate)
                }
            }
            .alert("Delete Records", isPresented: $showingDeleteAlert, presenting: dateToDelete) { date in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    performDelete(for: date)
                }
            } message: { date in
                Text("Are you sure you want to delete all telemetry records for \(dateFormatter.string(from: date))?")
            }
            .onAppear {
                refreshLogDates()
            }
        }
    }

    private func performDelete(for date: Date) {
        isLoading = true
        
        // Delete in background to avoid UI freezing
        DispatchQueue.global(qos: .userInitiated).async {
            self.presenter.deleteRecordsForDate(date)
            
            // Refresh the list on the main thread
            DispatchQueue.main.async {
                self.refreshLogDates()
            }
        }
    }
    
    private func loadRecordsForDate(_ date: Date) {
        isLoading = true
        
        // Use DispatchQueue to avoid UI freezing when loading large datasets
        DispatchQueue.global(qos: .userInitiated).async {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            let records = presenter.getTelemetryRecords(from: startOfDay, to: endOfDay)
            
            // Return to main thread for UI updates
            DispatchQueue.main.async {
                recordsForDate = records
                selectedDate = date
                isLoading = false
                showingDataDetail = true
            }
        }
    }

    private func deleteRecordsForDate(_ date: Date) {
        // Show confirmation alert
        let dateString = dateFormatter.string(from: date)
        let alert = UIAlertController(
            title: "Delete Records",
            message: "Are you sure you want to delete all telemetry records for \(dateString)?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            // Show loading indicator
            isLoading = true
            
            // Delete in background to avoid UI freezing
            DispatchQueue.global(qos: .userInitiated).async {
                self.presenter.deleteRecordsForDate(date)
                
                // Refresh the list on the main thread
                DispatchQueue.main.async {
                    self.refreshLogDates()
                }
            }
        })
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func refreshLogDates() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let dates = presenter.getAvailableDates()
            
            DispatchQueue.main.async {
                logDates = dates
                isLoading = false
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
}

struct TelemetryLogDetailView: View {
    let date: Date
    let records: [NSManagedObject]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSegment = 0
    
    var body: some View {
        NavigationView {
            VStack {
                // Data summary header
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(records.count) Records")
                        .font(.headline)
                    
                    if let firstRecord = records.first,
                       let firstTimestamp = firstRecord.value(forKey: "timestamp") as? Date,
                       let lastRecord = records.last,
                       let lastTimestamp = lastRecord.value(forKey: "timestamp") as? Date {
                        
                        Text("From: \(timeFormatter.string(from: firstTimestamp))")
                            .font(.subheadline)
                        Text("To: \(timeFormatter.string(from: lastTimestamp))")
                            .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
                
                Divider()
                
                // Record list
                List {
                    ForEach(0..<records.count, id: \.self) { index in
                        let record = records[index]
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Record #\(record.value(forKey: "msgNum") as? Int32 ?? Int32(index))")
                                    .font(.headline)
                                Spacer()
                                if let timestamp = record.value(forKey: "timestamp") as? Date {
                                    Text(timeFormatter.string(from: timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Location:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.6f", record.value(forKey: "lat") as? Double ?? 0)), \(String(format: "%.6f", record.value(forKey: "lon") as? Double ?? 0))")
                                        .font(.caption2)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Altitude:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", record.value(forKey: "alt") as? Double ?? 0)) m")
                                        .font(.caption2)
                                }
                            }
                            
                            HStack {
                                Label("\(record.value(forKey: "numSats") as? Int16 ?? 0) satellites", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(record.value(forKey: "gpsFix") as? String ?? "Unknown Fix")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(dateFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }
}

struct TelemetryDetailView: View {
    let date: Date
    let records: [TelemetryRecord]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(records) { record in
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Record #\(record.msgNum)")
                                .font(.headline)
                            Spacer()
                            if let timestamp = record.timestamp {
                                Text(timeFormatter.string(from: timestamp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("Location: \(String(format: "%.6f", record.lat)), \(String(format: "%.6f", record.lon))")
                            .font(.caption)
                        
                        Text("Altitude: \(String(format: "%.1f", record.alt)) m")
                            .font(.caption)
                        
                        Text("Satellites: \(record.numSats)")
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(dateFormatter.string(from: date))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }
}



#Preview {
    let service = BluetoothService()
    let presenter = MainPresenter(bluetoothService: service)
    return TelemetryDataView(presenter: presenter)
}
