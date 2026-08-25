import Foundation

public struct Note: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var title: String
    public var content: String
    public var summary: String
    public var transcript: String
    public var date: Date
    public var modifiedDate: Date
    public var audioFileName: String?
    public var duration: TimeInterval

    public init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        summary: String = "",
        transcript: String = "",
        date: Date = Date(),
        modifiedDate: Date = Date(),
        audioFileName: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.summary = summary
        self.transcript = transcript
        self.date = date
        self.modifiedDate = modifiedDate
        self.audioFileName = audioFileName
        self.duration = duration
    }

    public var displayTitle: String {
        title.isEmpty ? "Untitled Note" : title
    }
}
