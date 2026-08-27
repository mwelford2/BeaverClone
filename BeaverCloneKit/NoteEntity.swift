import CoreData
import Foundation

@objc(NoteEntity)
public class NoteEntity: NSManagedObject {
    // These attributes are optional at the Core Data model level (required by
    // NSPersistentCloudKitContainer, which mirrors records with no non-null constraints),
    // so the Swift properties must be Optional too — a non-Optional @NSManaged property
    // backed by a nil value causes a fatal fault.
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var content: String?
    @NSManaged public var summary: String?
    @NSManaged public var transcript: String?
    @NSManaged public var date: Date?
    @NSManaged public var modifiedDate: Date?
    @NSManaged public var audioFileName: String?
    @NSManaged public var duration: Double
    @NSManaged public var audioAsset: Data?
    /// JSON-encoded [WordTiming], stored as Data since Core Data has no native array attribute type.
    @NSManaged public var wordTimingsData: Data?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<NoteEntity> {
        NSFetchRequest<NoteEntity>(entityName: "NoteEntity")
    }
}

extension NoteEntity {
    func apply(from note: Note) {
        id = note.id
        title = note.title
        content = note.content
        summary = note.summary
        transcript = note.transcript
        date = note.date
        modifiedDate = note.modifiedDate
        audioFileName = note.audioFileName
        duration = note.duration
        wordTimingsData = note.wordTimings.isEmpty ? nil : try? JSONEncoder().encode(note.wordTimings)
    }

    func toNote() -> Note {
        let timings = wordTimingsData.flatMap { try? JSONDecoder().decode([WordTiming].self, from: $0) } ?? []
        return Note(
            id: id ?? UUID(),
            title: title ?? "",
            content: content ?? "",
            summary: summary ?? "",
            transcript: transcript ?? "",
            date: date ?? Date(),
            modifiedDate: modifiedDate ?? Date(),
            audioFileName: audioFileName,
            duration: duration,
            wordTimings: timings
        )
    }
}
