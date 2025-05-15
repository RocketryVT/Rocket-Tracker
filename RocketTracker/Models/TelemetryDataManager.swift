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
    
    // Get all telemetry records for a specific date range
    func getTelemetryRecords(from startDate: Date? = nil, to endDate: Date? = nil) -> [TelemetryRecord] {
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<TelemetryRecord>(entityName: "TelemetryRecord")

        
        // Add date predicates if specified
        var predicates: [NSPredicate] = []
        
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
    
    // Get all available dates that have telemetry records
    func getAvailableDates() -> [Date] {
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "TelemetryRecord")
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

    func deleteRecordsForDate(_ date: Date) {
        let context = persistentContainer.viewContext
        let calendar = Calendar.current
        
        // Get start and end of the day
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        print("TelemetryDataManager: Deleting records between \(startOfDay) and \(endOfDay)")
        
        // Create fetch request with date range predicate
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "TelemetryRecord")
        fetchRequest.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp < %@", 
            startOfDay as NSDate, 
            endOfDay as NSDate
        )
        
        do {
            let dateRecords = try context.fetch(fetchRequest)
            print("Found \(dateRecords.count) records to delete")
            
            if dateRecords.isEmpty {
                print("No records found for this date")
                return
            }
            
            for record in dateRecords {
                context.delete(record)
            }
            
            try context.save()
            print("Successfully deleted \(dateRecords.count) records")
            
            // Force persistent store save
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    print("Failed to save context after deletion: \(error)")
                }
            }
            print("Saved changes to persistent store")
            
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