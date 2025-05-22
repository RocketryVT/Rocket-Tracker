import Foundation

struct TelemetryData: Codable {
    let deviceID: UInt32
    let time_since_boot: Int
    let msg_num: Int
    let lat: Double
    let lon: Double
    let alt: Double
    let num_sats: Int
    let gps_fix: String
    let gps_time: UTCTime
    let baro_alt: Double
    // Add other properties as needed
}

struct UTCTime: Codable {
    let itow: Int
    let time_accuracy_estimate_ns: Int
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let min: Int
    let sec: Int
    let nanos: Int
    let valid: Int
}

struct ReceivedMessage: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ReceivedMessage, rhs: ReceivedMessage) -> Bool {
        return lhs.id == rhs.id
    }
}
