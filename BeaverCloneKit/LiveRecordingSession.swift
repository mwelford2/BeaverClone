import Foundation
import AVFoundation
import Combine

/// Drives a recording end-to-end with live feedback. A placeholder `Note` is created in the
/// store the instant recording starts, so it appears in the list and can be navigated to
/// immediately. As `AudioRecorder` finishes each short segment, this transcribes it, appends to
/// a running transcript, and persists the update to that same note — so it reads as "live"
/// whether the user is watching NoteDetailView or has navigated away. It periodically re-runs
/// summarization against the transcript so far too. On stop, it stitches the segment files into
/// one final audio file and does a last title/summary pass, same as a non-live recording.
@MainActor
public final class LiveRecordingSession: NSObject, ObservableObject {
    @Published public private(set) var liveTranscript: String = ""
    @Published public private(set) var liveSummary: String = ""
    @Published public private(set) var liveTitle: String = ""
    @Published public private(set) var isFinalizing = false
    /// The id of the note created for the current (or just-finished) recording, so views can
    /// tell whether a given note is the one this session is live-updating.
    @Published public private(set) var noteID: UUID?

    public let recorder = AudioRecorder()
    private let noteStore: NoteStore

    /// How many completed segments between live re-summarizations.
    private let summarizeEverySegments = 2

    private var wordTimings: [WordTiming] = []
    private var transcriptParts: [String] = []
    private var segmentsSinceLastSummary = 0
    private var pendingSegmentTasks: [Task<Void, Never>] = []
    private var summarizeTask: Task<Void, Never>?
    private var recordingStartDate = Date()

    public init(noteStore: NoteStore) {
        self.noteStore = noteStore
        super.init()
        recorder.onSegmentFinished = { [weak self] segment in
            self?.handleSegmentFinished(segment)
        }
    }

    public var isRecording: Bool { recorder.isRecording }
    public var elapsedTime: TimeInterval { recorder.elapsedTime }
    public var permissionDenied: Bool { recorder.permissionDenied }

    /// Creates the placeholder note right away and starts recording. Returns the new note's id
    /// so the caller can navigate to it immediately.
    @discardableResult
    public func startRecording() -> UUID {
        liveTranscript = ""
        liveSummary = ""
        liveTitle = ""
        wordTimings = []
        transcriptParts = []
        segmentsSinceLastSummary = 0
        pendingSegmentTasks = []
        recordingStartDate = Date()

        let placeholder = Note(title: "Recording…", date: recordingStartDate, modifiedDate: recordingStartDate)
        noteID = placeholder.id
        noteStore.addNote(placeholder)

        recorder.startRecording()
        return placeholder.id
    }

    public func cancelRecording() {
        summarizeTask?.cancel()
        for task in pendingSegmentTasks { task.cancel() }
        pendingSegmentTasks = []
        recorder.cancelRecording()
        if let noteID, let note = noteStore.notes.first(where: { $0.id == noteID }) {
            noteStore.deleteNote(note)
        }
        noteID = nil
    }

    private func handleSegmentFinished(_ segment: RecordingSegment) {
        let task = Task { [weak self] in
            guard let self else { return }
            guard let text = await self.transcribeSegment(segment) else { return }
            guard !Task.isCancelled else { return }

            if !text.text.isEmpty {
                self.transcriptParts.append(text.text)
                self.liveTranscript = self.transcriptParts.joined(separator: " ")
                self.persistLiveState()
            }
            self.wordTimings.append(contentsOf: text.wordTimings)

            self.segmentsSinceLastSummary += 1
            if self.segmentsSinceLastSummary >= self.summarizeEverySegments {
                self.segmentsSinceLastSummary = 0
                self.refreshLiveSummary()
            }
        }
        pendingSegmentTasks.append(task)
    }

    private func transcribeSegment(_ segment: RecordingSegment) async -> (text: String, wordTimings: [WordTiming])? {
        let url = AudioFileStore.shared.url(for: segment.fileName)
        guard let result = try? await OpenAIService.shared.transcribe(fileURL: url) else { return nil }
        let offsetTimings = result.wordTimings.map {
            WordTiming(word: $0.word, start: $0.start + segment.startOffset, end: $0.end + segment.startOffset)
        }
        return (result.text, offsetTimings)
    }

    private func refreshLiveSummary() {
        summarizeTask?.cancel()
        let transcriptSoFar = liveTranscript
        guard !transcriptSoFar.isEmpty else { return }

        summarizeTask = Task { [weak self] in
            guard let self else { return }
            guard let result = try? await OpenAIService.shared.summarize(transcript: transcriptSoFar) else { return }
            guard !Task.isCancelled else { return }
            self.liveSummary = result.summary
            if !result.title.isEmpty {
                self.liveTitle = result.title
            }
            self.persistLiveState()
        }
    }

    /// Pushes the current in-memory live transcript/summary/title into the placeholder note in
    /// the store, so it's reflected even for observers not reading this session's own published
    /// properties directly (e.g. the note list card, or NoteDetailView after a relaunch).
    private func persistLiveState() {
        guard let noteID, var note = noteStore.notes.first(where: { $0.id == noteID }) else { return }
        note.transcript = liveTranscript
        note.summary = liveSummary
        if !liveTitle.isEmpty {
            note.title = liveTitle
        }
        noteStore.updateNote(note)
    }

    /// Stops recording, waits for any in-flight segment transcriptions, stitches the segment
    /// audio into one file, and runs a final summarization pass over the complete transcript
    /// (the live, in-progress summary may be one or two segments behind), then saves that as
    /// the final state of the note created at the start of recording. Returns nil if there was
    /// nothing to save. `transcriptionFailed` is true when every segment failed to transcribe
    /// (e.g. the API is unreachable) — the note is still saved (with its audio intact, just no
    /// transcript/summary) so the recording itself is never silently lost; the caller can use
    /// the flag to surface an error alongside it.
    public func finishRecording() async -> (note: Note, transcriptionFailed: Bool)? {
        guard let stopped = recorder.stopRecording(), let noteID else { return nil }
        isFinalizing = true
        defer { isFinalizing = false }

        for task in pendingSegmentTasks { await task.value }
        pendingSegmentTasks = []
        summarizeTask?.cancel()

        let finalFileName = await Self.concatenate(segments: stopped.segments)
        let sortedTimings = wordTimings.sorted { $0.start < $1.start }
        let transcript = transcriptParts.isEmpty ? liveTranscript : transcriptParts.joined(separator: " ")
        let transcriptionFailed = transcript.isEmpty && !stopped.segments.isEmpty

        var note = noteStore.notes.first(where: { $0.id == noteID })
            ?? Note(id: noteID, title: "Recording…", date: recordingStartDate)
        note.title = liveTitle.isEmpty ? "New Recording" : liveTitle
        note.transcript = transcript
        note.audioFileName = finalFileName
        note.duration = stopped.duration
        note.wordTimings = sortedTimings

        if !transcript.isEmpty, let summarized = try? await OpenAIService.shared.summarize(transcript: transcript) {
            note.summary = summarized.summary
            if !summarized.title.isEmpty {
                note.title = summarized.title
            }
        } else if !liveSummary.isEmpty {
            note.summary = liveSummary
        }

        noteStore.updateNote(note)
        self.noteID = nil
        return (note, transcriptionFailed)
    }

    /// Joins the per-segment .m4a files into one continuous file via AVMutableComposition so
    /// the saved note has a single playable audio asset, same as a non-live recording. Cleans
    /// up every segment file except one that ends up being reused as the final result (kept,
    /// not deleted, since it's now what the note points at).
    private static func concatenate(segments: [RecordingSegment]) async -> String? {
        guard !segments.isEmpty else { return nil }
        if segments.count == 1 {
            return segments[0].fileName
        }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return segments.first?.fileName
        }

        var cursor = CMTime.zero
        for segment in segments {
            let url = AudioFileStore.shared.url(for: segment.fileName)
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .audio).first else { continue }
            guard let duration = try? await asset.load(.duration) else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            try? track.insertTimeRange(range, of: assetTrack, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }

        let outputFileName = "\(UUID().uuidString).m4a"
        let outputURL = AudioFileStore.shared.url(for: outputFileName)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            deleteAll(segments)
            return nil
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status == .completed {
            deleteAll(segments)
            return outputFileName
        } else {
            // Export failed — fall back to keeping just the first segment rather than losing
            // the recording entirely; clean up the rest.
            let keep = segments.first
            deleteAll(segments.dropFirst().map { $0 })
            return keep?.fileName
        }
    }

    private static func deleteAll(_ segments: [RecordingSegment]) {
        for segment in segments {
            AudioFileStore.shared.delete(fileName: segment.fileName)
        }
    }
}
