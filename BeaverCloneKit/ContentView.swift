import SwiftUI
#if DEBUG
import AVFoundation
#endif

public struct ContentView: View {
    @StateObject private var noteStore = NoteStore()
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var showingSettings = false
    @State private var isProcessingNewNote = false
    @State private var processingError: String?
    @State private var selectedNote: Note?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {}

    public var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                // NavigationSplitView's sidebar->detail push is unreliable on compact-width
                // iOS 16 (the app's minimum target) — navigationDestination attached to the
                // detail column silently never fires. A plain NavigationStack, where the
                // destination lives directly in the same stack as the pushing NavigationLink,
                // doesn't have that bug and is what iPhone needs anyway (single column).
                NavigationStack {
                    listContent
                        .navigationDestination(for: Note.self) { note in
                            NoteDetailView(noteStore: noteStore, note: note)
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
        .overlay(alignment: .bottom) {
            if audioRecorder.isRecording {
                RecordingBanner(recorder: audioRecorder, onStop: finishRecording, onCancel: audioRecorder.cancelRecording)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isProcessingNewNote {
                ProcessingBanner()
                    .padding()
            }
        }
        .animation(.default, value: audioRecorder.isRecording)
    }

    private var splitView: some View {
        NavigationSplitView {
            listContent
        } detail: {
            if let selectedNote {
                NoteDetailView(noteStore: noteStore, note: selectedNote)
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
                    .fill(audioRecorder.isRecording ? Color.red : BeaverTheme.accent)
                    .frame(width: 64, height: 64)
                    .shadow(color: (audioRecorder.isRecording ? Color.red : BeaverTheme.accent).opacity(0.35), radius: 10, y: 4)
                Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessingNewNote)
    }

    private func toggleRecording() {
        if audioRecorder.isRecording {
            finishRecording()
        } else {
            audioRecorder.startRecording()
        }
    }

    private func finishRecording() {
        guard let result = audioRecorder.stopRecording() else { return }
        isProcessingNewNote = true

        Task {
            do {
                let audioURL = AudioFileStore.shared.url(for: result.fileName)
                let (transcript, wordTimings) = try await OpenAIService.shared.transcribeAudio(fileURL: audioURL)

                var note = Note(
                    title: "New Recording",
                    transcript: transcript,
                    audioFileName: result.fileName,
                    duration: result.duration,
                    wordTimings: wordTimings
                )

                if let summarized = try? await OpenAIService.shared.summarize(transcript: transcript) {
                    note.summary = summarized.summary
                    if !summarized.title.isEmpty {
                        note.title = summarized.title
                    }
                }

                await MainActor.run {
                    noteStore.addNote(note)
                    isProcessingNewNote = false
                }
            } catch {
                await MainActor.run {
                    processingError = error.localizedDescription
                    isProcessingNewNote = false
                }
            }
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

private struct RecordingBanner: View {
    @ObservedObject var recorder: AudioRecorder
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Text(formattedTime(recorder.elapsedTime))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(BeaverTheme.navy)
            Spacer()
            Button("Cancel", role: .destructive, action: onCancel)
            Button("Done", action: onStop)
                .buttonStyle(.borderedProminent)
                .tint(BeaverTheme.accent)
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
