import CoreData
import Foundation

@objc(NoteEntity)
public class NoteEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var content: String
    @NSManaged public var summary: String
    @NSManaged public var transcript: String
    @NSManaged public var date: Date
    @NSManaged public var modifiedDate: Date
    @NSManaged public var audioFileName: String?
    @NSManaged public var duration: Double
    @NSManaged public var audioAsset: Data?

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
    }

    func toNote() -> Note {
        Note(
            id: id,
            title: title,
            content: content,
            summary: summary,
            transcript: transcript,
            date: date,
            modifiedDate: modifiedDate,
            audioFileName: audioFileName,
            duration: duration
        )
    }
}
