import SwiftUI

public struct ContentView: View {
    @StateObject private var noteStore = NoteStore()
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var showingSettings = false
    @State private var isProcessingNewNote = false
    @State private var processingError: String?
    @State private var selectedNote: Note?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            ZStack(alignment: .bottom) {
                BeaverTheme.groupedBackground.ignoresSafeArea()

                Group {
                    if noteStore.notes.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(noteStore.notes) { note in
                                    Button {
                                        selectedNote = note
                                    } label: {
                                        NoteCard(note: note, isSelected: selectedNote?.id == note.id)
                                    }
                                    .buttonStyle(.plain)
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
                ToolbarItem {
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
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
                let transcript = try await OpenAIService.shared.transcribeAudio(fileURL: audioURL)

                var note = Note(
                    title: "New Recording",
                    transcript: transcript,
                    audioFileName: result.fileName,
                    duration: result.duration
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
