import CoreData
import CloudKit

public final class PersistenceController {
    public static let shared = PersistenceController()

    public let container: NSPersistentCloudKitContainer

    private init() {
        let model = Self.makeModel()
        container = NSPersistentCloudKitContainer(name: "BeaverClone", managedObjectModel: model)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store description found")
        }

        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.example.beaverclone"
        )

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // A failed CloudKit-backed store load is typically caused by missing
                // entitlements/iCloud sign-in during local development, not corrupt data.
                print("PersistenceController failed to load store: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("Failed to pin query generation: \(error)")
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "NoteEntity"
        entity.managedObjectClassName = NSStringFromClass(NoteEntity.self)

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = type
            attr.isOptional = optional
            return attr
        }

        let idAttr = attribute("id", .UUIDAttributeType)
        let titleAttr = attribute("title", .stringAttributeType)
        let contentAttr = attribute("content", .stringAttributeType)
        let summaryAttr = attribute("summary", .stringAttributeType)
        let transcriptAttr = attribute("transcript", .stringAttributeType)
        let dateAttr = attribute("date", .dateAttributeType)
        let modifiedDateAttr = attribute("modifiedDate", .dateAttributeType)
        let audioFileNameAttr = attribute("audioFileName", .stringAttributeType, optional: true)
        let durationAttr = attribute("duration", .doubleAttributeType)
        let audioAssetAttr = attribute("audioAsset", .binaryDataAttributeType, optional: true)
        audioAssetAttr.allowsExternalBinaryDataStorage = true

        entity.properties = [
            idAttr, titleAttr, contentAttr, summaryAttr, transcriptAttr,
            dateAttr, modifiedDateAttr, audioFileNameAttr, durationAttr, audioAssetAttr
        ]

        model.entities = [entity]
        return model
    }

    public func saveContext() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
