import SwiftUI

public struct NoteDetailView: View {
    @ObservedObject var noteStore: NoteStore
    @StateObject private var player = AudioPlayer()
    @State private var note: Note
    @State private var showingEditSheet = false
    @State private var selectedTab: Tab = .summary

    private enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case transcript = "Transcript"
        case notes = "Notes"
        var id: String { rawValue }
    }

    public init(noteStore: NoteStore, note: Note) {
        self.noteStore = noteStore
        _note = State(initialValue: note)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let fileName = note.audioFileName {
                PlaybackControls(player: player, fileName: fileName)
                    .padding()
                    .background(BeaverTheme.cardBackground)
            }

            Picker("View", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .tint(BeaverTheme.accent)
            .padding()

            ScrollView {
                Text(currentText.isEmpty ? "Nothing here yet." : currentText)
                    .font(.body)
                    .foregroundStyle(currentText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .background(BeaverTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(note.displayTitle)
        .toolbar {
            ToolbarItem {
                Button(action: { showingEditSheet = true }) {
                    Label("Edit", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditNoteView(note: note) { updated in
                note = updated
                noteStore.updateNote(updated)
            }
        }
        .onAppear {
            if let fileName = note.audioFileName {
                player.load(fileName: fileName)
            }
        }
    }

    private var currentText: String {
        switch selectedTab {
        case .summary: return note.summary
        case .transcript: return note.transcript
        case .notes: return note.content
        }
    }
}

private struct PlaybackControls: View {
    @ObservedObject var player: AudioPlayer
    let fileName: String

    var body: some View {
        HStack(spacing: 12) {
            Button(action: player.togglePlayback) {
                ZStack {
                    Circle()
                        .fill(BeaverTheme.accent)
                        .frame(width: 44, height: 44)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...(max(player.duration, 1))
            )
            .tint(BeaverTheme.accent)

            Text(formattedTime(player.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
