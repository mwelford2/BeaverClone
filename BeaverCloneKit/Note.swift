import Foundation

public struct WordTiming: Codable, Equatable, Hashable {
    public var word: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(word: String, start: TimeInterval, end: TimeInterval) {
        self.word = word
        self.start = start
        self.end = end
    }
}

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
    /// Per-word timestamps from transcription, when the endpoint supports `timestamp_granularities=word`.
    /// Empty when unavailable — transcript highlighting then falls back to proportional timing.
    public var wordTimings: [WordTiming]

    public init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        summary: String = "",
        transcript: String = "",
        date: Date = Date(),
        modifiedDate: Date = Date(),
        audioFileName: String? = nil,
        duration: TimeInterval = 0,
        wordTimings: [WordTiming] = []
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
        self.wordTimings = wordTimings
    }

    public var displayTitle: String {
        title.isEmpty ? "Untitled Note" : title
    }
}
