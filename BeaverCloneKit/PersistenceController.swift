import CoreData
import CloudKit
import Foundation

public final class PersistenceController {
    public static let shared = PersistenceController()

    public let container: NSPersistentContainer
    public let cloudKitEnabled: Bool

    private static let cloudKitContainerIdentifier = "iCloud.com.example.beaverclone"

    private init() {
        let model = Self.makeModel()

        // NSPersistentCloudKitContainer hard-crashes (SIGTRAP, unrecoverable — not a catchable
        // Swift error) inside CloudKit's own setup code if the running binary lacks a matching
        // com.apple.developer.icloud-services entitlement. This happens with ad-hoc/self-signed
        // builds (Feather, AltStore, etc.) that don't carry the original signing team's
        // entitlements, even on a device that's otherwise signed into iCloud. Only attempt
        // CloudKit when both signals check out: the device has an iCloud account AND this
        // specific binary was actually signed with the iCloud entitlement.
        let canUseCloudKit = FileManager.default.ubiquityIdentityToken != nil && Self.isSignedWithCloudKitEntitlement()

        if canUseCloudKit {
            let cloudContainer = NSPersistentCloudKitContainer(name: "BeaverClone", managedObjectModel: model)
            if let description = cloudContainer.persistentStoreDescriptions.first {
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: Self.cloudKitContainerIdentifier
                )
            }
            container = cloudContainer
            cloudKitEnabled = true
        } else {
            container = NSPersistentContainer(name: "BeaverClone", managedObjectModel: model)
            cloudKitEnabled = false
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
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

    /// Reads the app's own embedded provisioning profile (public, on-disk — no private API)
    /// to check whether it actually declares the iCloud/CloudKit entitlement. Ad-hoc or
    /// self-resigned builds (Feather, AltStore, etc.) typically carry a profile with no
    /// iCloud capability at all, which is exactly the case that crashes NSPersistentCloudKitContainer.
    private static func isSignedWithCloudKitEntitlement() -> Bool {
        guard let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let profileData = try? Data(contentsOf: profileURL),
              let profileString = String(data: profileData, encoding: .isoLatin1) else {
            // No embedded profile at all (e.g. some ad-hoc resigning tools strip it) — assume no entitlement.
            return false
        }

        guard let xmlStart = profileString.range(of: "<?xml"),
              let xmlEnd = profileString.range(of: "</plist>") else {
            return false
        }

        let xmlString = String(profileString[xmlStart.lowerBound..<xmlEnd.upperBound])
        guard let xmlData = xmlString.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let services = entitlements["com.apple.developer.icloud-services"] as? [String] else {
            return false
        }

        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "NoteEntity"
        entity.managedObjectClassName = NSStringFromClass(NoteEntity.self)

        // NSPersistentCloudKitContainer requires every attribute mirrored to CloudKit
        // to be optional (CloudKit records don't enforce non-null constraints).
        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = type
            attr.isOptional = true
            return attr
        }

        let idAttr = attribute("id", .UUIDAttributeType)
        let titleAttr = attribute("title", .stringAttributeType)
        let contentAttr = attribute("content", .stringAttributeType)
        let summaryAttr = attribute("summary", .stringAttributeType)
        let transcriptAttr = attribute("transcript", .stringAttributeType)
        let dateAttr = attribute("date", .dateAttributeType)
        let modifiedDateAttr = attribute("modifiedDate", .dateAttributeType)
        let audioFileNameAttr = attribute("audioFileName", .stringAttributeType)
        let durationAttr = attribute("duration", .doubleAttributeType)
        let audioAssetAttr = attribute("audioAsset", .binaryDataAttributeType)
        audioAssetAttr.allowsExternalBinaryDataStorage = true
        let wordTimingsAttr = attribute("wordTimingsData", .binaryDataAttributeType)

        entity.properties = [
            idAttr, titleAttr, contentAttr, summaryAttr, transcriptAttr,
            dateAttr, modifiedDateAttr, audioFileNameAttr, durationAttr, audioAssetAttr,
            wordTimingsAttr
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
