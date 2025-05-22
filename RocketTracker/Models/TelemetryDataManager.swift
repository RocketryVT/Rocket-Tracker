import Foundation
import CoreData
import Combine

class TelemetryDataManager {
    private let persistentContainer: NSPersistentContainer
    
    init() {
        persistentContainer = NSPersistentContainer(name: "RocketTracker")
        
        // Load persistent stores synchronously to ensure they're available
        persistentContainer.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("Failed to load Core Data stack: \(error), \(error.userInfo)")
                fatalError("Failed to load Core Data stack: \(error), \(error.userInfo)")
            } else {
                print("Successfully loaded Core Data store at: \(storeDescription.url?.absoluteString ?? "unknown")")
            }
        }
        
        // Enable automatic merging of changes from parent contexts
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // Log new telemetry data
    func logTelemetry(_ data: TelemetryData) {
        let context = persistentContainer.viewContext
        
        let record = NSEntityDescription.insertNewObject(forEntityName: "TelemetryRecord", into: context) as! TelemetryRecord


        record.timestamp = Date()
        record.deviceID = Int32(data.deviceID)
        record.lat = data.lat
        record.lon = data.lon
        record.alt = data.alt
        record.numSats = Int16(data.num_sats)
        record.gpsFix = data.gps_fix
        record.baroAlt = data.baro_alt
        record.timeSinceBoot = Int32(data.time_since_boot)
        record.msgNum = Int32(data.msg_num)
        record.year = Int16(data.gps_time.year)
        record.month = Int16(data.gps_time.month)
        record.day = Int16(data.gps_time.day)
        record.hour = Int16(data.gps_time.hour)
        record.minute = Int16(data.gps_time.min)
        record.second = Int16(data.gps_time.sec)
        
        // Save the context
        do {
            try context.save()
        } catch {
            print("Failed to save telemetry record: \(error)")
        }
    }
    
    // Get all telemetry records for a specific device and date range
    func getTelemetryRecords(deviceID: UInt32? = nil, from startDate: Date? = nil, to endDate: Date? = nil) -> [NSManagedObject] {
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "TelemetryRecord")
        
        // Add date and device predicates if specified
        var predicates: [NSPredicate] = []
        
        if let deviceID = deviceID {
            let devicePredicate = NSPredicate(format: "deviceID == %d", Int32(deviceID))
            predicates.append(devicePredicate)
        }
        
        if let startDate = startDate {
            let startPredicate = NSPredicate(format: "timestamp >= %@", startDate as NSDate)
            predicates.append(startPredicate)
        }
        
        if let endDate = endDate {
            let endPredicate = NSPredicate(format: "timestamp <= %@", endDate as NSDate)
            predicates.append(endPredicate)
        }
        
        if !predicates.isEmpty {
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        // Sort by timestamp
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Failed to fetch telemetry records: \(error)")
            return []
        }
    }
    
    // Get all available dates that have telemetry records, optionally filtered by deviceID
    func getAvailableDates(forDeviceID deviceID: UInt32? = nil) -> [Date] {
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "TelemetryRecord")
        
        if let deviceID = deviceID {
            fetchRequest.predicate = NSPredicate(format: "deviceID == %d", Int32(deviceID))
        }
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            let records = try context.fetch(fetchRequest)
            print("Found \(records.count) telemetry records in database")
            
            let calendar = Calendar.current
            
            // Extract just the dates (no time component) and remove duplicates
            let dates = records.compactMap { 
                if let timestamp = $0.value(forKey: "timestamp") as? Date {
                    return calendar.startOfDay(for: timestamp)
                }
                return nil
            }
            let uniqueDates = Array(Set(dates)).sorted()
            print("Found \(uniqueDates.count) unique dates with telemetry data")
            return uniqueDates
        } catch {
            print("Failed to fetch telemetry dates: \(error)")
            return []
        }
    }

    // Get all unique device IDs in the database
    func getAllDeviceIDs() -> [UInt32] {
        let context = persistentContainer.viewContext
        
        // Change the generic type to NSDictionary instead of NSManagedObject
        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: "TelemetryRecord")
        
        // We need to use a distinct result type for unique device IDs
        fetchRequest.returnsDistinctResults = true
        fetchRequest.propertiesToFetch = ["deviceID"]
        fetchRequest.resultType = .dictionaryResultType
        
        do {
            // Now our fetch result type matches our generic type
            let results = try context.fetch(fetchRequest)
            let deviceIDs = results.compactMap { result in
                if let deviceID = result["deviceID"] as? Int32 {
                    return UInt32(deviceID)
                }
                return nil
            }
            return deviceIDs
        } catch {
            print("Failed to fetch device IDs: \(error)")
            return []
        }
    }
    
    // Delete records older than a specified date
    func deleteRecords(olderThan date: Date) {
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "TelemetryRecord")
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        
        do {
            let oldRecords = try context.fetch(fetchRequest)
            print("Deleting \(oldRecords.count) old records")
            
            for record in oldRecords {
                context.delete(record)
            }
            try context.save()
        } catch {
            print("Failed to delete old records: \(error)")
        }
    }

    // Delete records for a specific device and date
    func deleteRecordsForDate(_ date: Date, deviceID: UInt32? = nil) {
        let context = persistentContainer.viewContext
        let calendar = Calendar.current
        
        // Get start and end of the day
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Create fetch request with date range predicate
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "TelemetryRecord")
        
        var predicates = [
            NSPredicate(format: "timestamp >= %@ AND timestamp < %@", startOfDay as NSDate, endOfDay as NSDate)
        ]
        
        if let deviceID = deviceID {
            predicates.append(NSPredicate(format: "deviceID == %d", Int32(deviceID)))
        }
        
        if predicates.count > 1 {
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        } else {
            fetchRequest.predicate = predicates.first
        }
        
        do {
            let dateRecords = try context.fetch(fetchRequest)
            print("Found \(dateRecords.count) records to delete")
            
            for record in dateRecords {
                context.delete(record)
            }
            
            try context.save()
            print("Successfully deleted records")
        } catch {
            print("Failed to delete records for date: \(error)")
        }
    }

    func flushChanges() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("Changes saved to persistent store")
                
                // Reset the context to ensure clean state
                context.reset()
                print("Context reset to clean state")
            } catch {
                print("Error flushing changes: \(error)")
            }
        }
    }

    func forceSave() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("Successfully saved pending changes")
            } catch {
                print("Failed to save context: \(error)")
            }
        }
    }

    func verifyDataStore() {
        print("TelemetryDataManager: Verifying data store")
        
        // Check the persistent store URL
        if let storeURL = persistentContainer.persistentStoreCoordinator.persistentStores.first?.url {
            print("Persistent store URL: \(storeURL)")
            
            // Check if file exists
            let fileExists = FileManager.default.fileExists(atPath: storeURL.path)
            print("Store file exists: \(fileExists)")
            
            if fileExists {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
                    if let size = attributes[FileAttributeKey.size] as? NSNumber {
                        print("Store file size: \(size.intValue) bytes")
                    }
                    if let modDate = attributes[FileAttributeKey.modificationDate] as? Date {
                        print("Last modified: \(modDate)")
                    }
                } catch {
                    print("Error getting file attributes: \(error)")
                }
            }
        } else {
            print("No persistent store URL found")
        }
        
        // Check the number of records
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "TelemetryRecord")
        
        do {
            let count = try context.count(for: fetchRequest)
            print("Total record count: \(count)")
        } catch {
            print("Error counting records: \(error)")
        }
    }
}
// Helper for consistent date formatting in logs
private var dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
}()
