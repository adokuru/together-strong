import CoreData
import Foundation

@MainActor
final class WorkoutRepository {
    private let container: NSPersistentContainer

    init(inMemory: Bool = false) throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "WorkoutSnapshot"
        entity.managedObjectClassName = "NSManagedObject"
        let key = NSAttributeDescription()
        key.name = "accountKey"; key.attributeType = .stringAttributeType; key.isOptional = false
        let payload = NSAttributeDescription()
        payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
        entity.properties = [key, payload]
        entity.uniquenessConstraints = [["accountKey"]]
        model.entities = [entity]
        container = NSPersistentContainer(name: "TogetherStrong", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        if inMemory { description.type = NSInMemoryStoreType }
        else {
            var directory = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("WorkoutCache", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var attributes = URLResourceValues()
            attributes.isExcludedFromBackup = true
            try directory.setResourceValues(attributes)
            description.url = directory.appendingPathComponent("Workouts.sqlite")
            description.setOption(FileProtectionType.complete.rawValue as NSString,
                                  forKey: NSPersistentStoreFileProtectionKey)
        }
        container.persistentStoreDescriptions = [description]
        var failure: (any Error)?
        container.loadPersistentStores { _, error in failure = error }
        if failure != nil { throw StorageError.database }
    }

    private func object(for key: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "WorkoutSnapshot")
        request.predicate = NSPredicate(format: "accountKey == %@", key)
        request.fetchLimit = 1
        return try container.viewContext.fetch(request).first
    }

    func read(key: String) throws -> SyncRecord? {
        guard let object = try object(for: key), let data = object.value(forKey: "payload") as? Data else { return nil }
        return try JSONDecoder().decode(SyncRecord.self, from: data)
    }

    func write(_ record: SyncRecord, key: String) throws {
        let data = try JSONEncoder().encode(record)
        let context = container.viewContext
        do {
            let object = try object(for: key) ?? NSEntityDescription.insertNewObject(forEntityName: "WorkoutSnapshot", into: context)
            object.setValue(key, forKey: "accountKey")
            object.setValue(data, forKey: "payload")
            try context.save()
        } catch { context.rollback(); throw StorageError.database }
    }

    func remove(key: String) throws {
        let context = container.viewContext
        do {
            if let object = try object(for: key) { context.delete(object); try context.save() }
        } catch { context.rollback(); throw StorageError.database }
    }
}
