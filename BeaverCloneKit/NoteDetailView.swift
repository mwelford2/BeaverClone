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
                Group {
                    switch selectedTab {
                    case .summary:
                        SummaryHighlightView(summary: note.summary, player: player)
                    case .transcript:
                        TranscriptHighlightView(note: note, player: player)
                    case .notes:
                        Text(note.content.isEmpty ? "Nothing here yet." : note.content)
                            .font(.body)
                            .foregroundStyle(note.content.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
        .onDisappear {
            player.stop()
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
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

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

/// Word-by-word transcript highlighting synced to playback. Uses real per-word timestamps
/// when the transcription endpoint provided them; otherwise falls back to spreading words
/// evenly across the recording's duration so the feature still works with any OpenAI-compatible
/// server that only returns plain text.
private struct TranscriptHighlightView: View {
    let note: Note
    @ObservedObject var player: AudioPlayer

    private var words: [String] {
        note.transcript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Estimated (or real) [start, end) time range for each word, in display order.
    private var timings: [(start: TimeInterval, end: TimeInterval)] {
        if note.wordTimings.count == words.count, !note.wordTimings.isEmpty {
            return note.wordTimings.map { ($0.start, $0.end) }
        }

        let total = max(player.duration, note.duration, 1)
        let count = max(words.count, 1)
        let slice = total / Double(count)
        return (0..<count).map { i in
            (TimeInterval(i) * slice, TimeInterval(i + 1) * slice)
        }
    }

    var body: some View {
        if note.transcript.isEmpty {
            Text("Nothing here yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let currentTimings = timings
            FlowLayout(spacing: 4) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    Text(word)
                        .font(.body)
                        .foregroundStyle(color(for: index, timings: currentTimings))
                        .animation(.easeInOut(duration: 0.15), value: player.currentTime)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard index < currentTimings.count else { return }
                            player.seekAndPlay(to: currentTimings[index].start)
                        }
                }
            }
        }
    }

    private func color(for index: Int, timings: [(start: TimeInterval, end: TimeInterval)]) -> Color {
        guard index < timings.count else { return .primary }
        guard player.isPlaying || player.currentTime > 0 else { return .primary }
        return player.currentTime >= timings[index].start ? .primary : Color.secondary.opacity(0.4)
    }
}

/// Bullet-by-bullet summary highlighting. Summaries are synthesized text with no real timing
/// signal from the model, so points are greyed out proportionally across the recording's
/// duration in reading order — an approximation of "what's being talked about now."
private struct SummaryHighlightView: View {
    let summary: String
    @ObservedObject var player: AudioPlayer

    private var points: [String] {
        let lines = summary.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.isEmpty && !summary.isEmpty ? [summary] : lines
    }

    var body: some View {
        if summary.isEmpty {
            Text("Nothing here yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let total = max(player.duration, 1)
            let count = max(points.count, 1)
            let slice = total / Double(count)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Text(point)
                        .font(.body)
                        .foregroundStyle(color(for: index, slice: slice))
                        .animation(.easeInOut(duration: 0.2), value: player.currentTime)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.seekAndPlay(to: TimeInterval(index) * slice)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(for index: Int, slice: TimeInterval) -> Color {
        guard player.isPlaying || player.currentTime > 0 else { return .primary }
        let pointStart = TimeInterval(index) * slice
        return player.currentTime >= pointStart ? .primary : Color.secondary.opacity(0.4)
    }
}

/// Minimal flow layout so transcript words wrap naturally like a paragraph while still
/// being individually styleable (SwiftUI's HStack/Text can't per-word-color one Text block).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
