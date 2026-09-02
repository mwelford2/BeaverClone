import SwiftUI

/// Mirrors NoteDetailView's Summary/Transcript layout, but reads directly from a
/// LiveRecordingSession while recording is still in progress — no playback controls (there's
/// no finished audio file yet) and no tap-to-seek (no player to seek).
public struct LiveNoteView: View {
    @ObservedObject var session: LiveRecordingSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .summary

    private enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case transcript = "Transcript"
        var id: String { rawValue }
    }

    public init(session: LiveRecordingSession) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(session.isFinalizing ? "Finalizing…" : "Recording — updates live")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

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
                            liveText(session.liveSummary, placeholder: "Summary will appear here as you talk.")
                        case .transcript:
                            liveText(session.liveTranscript, placeholder: "Transcript will appear here as you talk.")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(BeaverTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(session.liveTitle.isEmpty ? "New Recording" : session.liveTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(BeaverTheme.accent)
    }

    @ViewBuilder
    private func liveText(_ text: String, placeholder: String) -> some View {
        if text.isEmpty {
            Text(placeholder)
                .foregroundStyle(.secondary)
        } else {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .animation(.default, value: text)
        }
    }
}
