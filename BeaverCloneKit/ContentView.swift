import SwiftUI
#if DEBUG
import AVFoundation
#endif

public struct ContentView: View {
    @StateObject private var noteStore: NoteStore
    @StateObject private var recordingSession: LiveRecordingSession
    @ObservedObject private var apiConfig = APIConfig.shared
    @State private var showingSettings = false
    @State private var showingNotConfiguredAlert = false
    @State private var isProcessingNewNote = false
    @State private var processingError: String?
    @State private var selectedNote: Note?
    @State private var navigationPath = NavigationPath()
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
        let store = NoteStore()
        _noteStore = StateObject(wrappedValue: store)
        _recordingSession = StateObject(wrappedValue: LiveRecordingSession(noteStore: store))
    }

    public var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                // NavigationSplitView's sidebar->detail push is unreliable on compact-width
                // iOS 16 (the app's minimum target) — navigationDestination attached to the
                // detail column silently never fires. A plain NavigationStack, where the
                // destination lives directly in the same stack as the pushing NavigationLink,
                // doesn't have that bug and is what iPhone needs anyway (single column).
                NavigationStack(path: $navigationPath) {
                    listContent
                        .navigationDestination(for: Note.self) { note in
                            NoteDetailView(noteStore: noteStore, note: note, liveSession: recordingSession)
                        }
                }
            } else {
                splitView
            }
            #else
            splitView
            #endif
        }
        .tint(BeaverTheme.accent)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Couldn't process recording", isPresented: .constant(processingError != nil), actions: {
            Button("OK") { processingError = nil }
        }, message: {
            Text(processingError ?? "")
        })
        .alert("Set up your API connection first", isPresented: $showingNotConfiguredAlert, actions: {
            Button("Open Settings") { showingSettings = true }
            Button("Cancel", role: .cancel) {}
        }, message: {
            Text("Beaver needs an API key and base URL to transcribe recordings. Add them in Settings before recording.")
        })
        .overlay(alignment: .bottom) {
            if recordingSession.isRecording {
                RecordingBanner(
                    session: recordingSession,
                    onStop: finishRecording,
                    onCancel: { cancelRecording() }
                )
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isProcessingNewNote {
                ProcessingBanner()
                    .padding()
            }
        }
        .animation(.default, value: recordingSession.isRecording)
        // Keep whichever view is showing the live note (list selection on iPad/Mac, or the
        // pushed navigationDestination on iPhone) pointed at the latest copy as it updates.
        .onChange(of: noteStore.notes) { notes in
            if let selectedNote, let updated = notes.first(where: { $0.id == selectedNote.id }) {
                self.selectedNote = updated
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            listContent
        } detail: {
            if let selectedNote {
                NoteDetailView(noteStore: noteStore, note: selectedNote, liveSession: recordingSession, initialTab: selectedNote.id == recordingSession.noteID ? .transcript : .summary)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Select a note")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var listContent: some View {
        ZStack(alignment: .bottom) {
            BeaverTheme.groupedBackground.ignoresSafeArea()

            Group {
                if noteStore.notes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(noteStore.notes) { note in
                                NavigationLink(value: note) {
                                    NoteCard(note: note, isSelected: selectedNote?.id == note.id)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    selectedNote = note
                                })
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        noteStore.deleteNote(note)
                                    }
                                }
                            }
                        }
                        .padding()
                        .padding(.bottom, 90)
                    }
                }
            }

            recordFAB
                .padding(.bottom, 24)
        }
        .navigationTitle("Notes")
        .toolbar {
            #if DEBUG
            ToolbarItem {
                Button("Seed") {
                    let fileName = Self.writeSilentAudioFile(duration: 4.0)
                    let note = Note(
                        title: "Debug Seed Note",
                        summary: "First point.\nSecond point.",
                        transcript: "This is a test transcript.",
                        audioFileName: fileName,
                        duration: 4.0
                    )
                    noteStore.addNote(note)
                }
            }
            #endif
            ToolbarItem {
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BeaverTheme.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(BeaverTheme.accent)
            }
            Text("No notes yet")
                .font(.headline)
                .foregroundStyle(BeaverTheme.navy)
            Text("Tap the microphone to record your first note.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordFAB: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .fill(recordingSession.isRecording ? Color.red : BeaverTheme.accent)
                    .frame(width: 64, height: 64)
                    .shadow(color: (recordingSession.isRecording ? Color.red : BeaverTheme.accent).opacity(0.35), radius: 10, y: 4)
                Image(systemName: recordingSession.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessingNewNote)
    }

    private func toggleRecording() {
        if recordingSession.isRecording {
            finishRecording()
        } else if !apiConfig.isConfigured {
            showingNotConfiguredAlert = true
        } else {
            let newNoteID = recordingSession.startRecording()
            navigateToLiveNote(id: newNoteID)
        }
    }

    /// Jumps straight to the note just created for this recording, open on its Transcript tab —
    /// pushed on the iPhone navigation stack, or selected directly in the split view on iPad/Mac.
    private func navigateToLiveNote(id: UUID) {
        guard let note = noteStore.notes.first(where: { $0.id == id }) else { return }
        selectedNote = note
        navigationPath.append(note)
    }

    private func finishRecording() {
        isProcessingNewNote = true

        Task {
            let result = await recordingSession.finishRecording()
            await MainActor.run {
                isProcessingNewNote = false
                if let result, result.transcriptionFailed {
                    processingError = "Saved the recording's audio, but couldn't reach the transcription service, so there's no transcript or summary — check your API settings in Settings."
                }
            }
        }
    }

    private func cancelRecording() {
        recordingSession.cancelRecording()
        selectedNote = nil
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    #if DEBUG
    /// Writes a silent .m4a of the given duration so debug-seeded notes have real playable
    /// audio (needed for playback controls / tap-to-seek to render and be testable via XCUITest).
    private static func writeSilentAudioFile(duration: TimeInterval) -> String {
        let fileName = "\(UUID().uuidString).m4a"
        let url = AudioFileStore.shared.url(for: fileName)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else {
            return fileName
        }
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
            buffer.frameLength = frameCount
            try? file.write(from: buffer)
        }
        return fileName
    }
    #endif
}

private struct NoteCard: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(BeaverTheme.accent.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BeaverTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.headline)
                    .foregroundStyle(BeaverTheme.navy)
                    .lineLimit(1)
                if !note.summary.isEmpty {
                    Text(note.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(note.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(BeaverTheme.cardBackground, in: RoundedRectangle(cornerRadius: BeaverTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: BeaverTheme.cardCornerRadius)
                .stroke(isSelected ? BeaverTheme.accent : .clear, lineWidth: 2)
        )
    }
}

/// Floats over the note list while recording. The live transcript/summary themselves are shown
/// in the note that was already pushed on record start (see ContentView.navigateToLiveNote) —
/// this banner just shows a short status line for when the user has navigated back to the list.
private struct RecordingBanner: View {
    @ObservedObject var session: LiveRecordingSession
    let onStop: () -> Void
    let onCancel: () -> Void

    /// Last few words of the live transcript, so the banner reads like a ticker rather than
    /// growing without bound.
    private var transcriptTail: String {
        let words = session.liveTranscript.split(separator: " ")
        let tail = words.suffix(14)
        return tail.isEmpty ? "" : "…" + tail.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text(formattedTime(session.elapsedTime))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(BeaverTheme.navy)
                Spacer()
                Button("Cancel", role: .destructive, action: onCancel)
                Button("Done", action: onStop)
                    .buttonStyle(.borderedProminent)
                    .tint(BeaverTheme.accent)
            }

            if !transcriptTail.isEmpty {
                Text(transcriptTail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .transition(.opacity)
                    .animation(.default, value: transcriptTail)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BeaverTheme.pillCornerRadius))
        .shadow(radius: 8, y: 2)
        .padding(.horizontal)
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct ProcessingBanner: View {
    var body: some View {
        HStack {
            ProgressView()
            Text("Transcribing and summarizing…")
                .font(.subheadline)
                .foregroundStyle(BeaverTheme.navy)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BeaverTheme.pillCornerRadius))
        .shadow(radius: 8, y: 2)
        .padding(.horizontal)
    }
}
