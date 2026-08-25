import SwiftUI

public struct EditNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var content: String
    private let note: Note
    private let onSave: (Note) -> Void

    public init(note: Note, onSave: @escaping (Note) -> Void) {
        self.note = note
        self.onSave = onSave
        _title = State(initialValue: note.title)
        _content = State(initialValue: note.content)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Notes") {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("Edit Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
        }
        .tint(BeaverTheme.accent)
    }

    private func save() {
        var updated = note
        updated.title = title
        updated.content = content
        onSave(updated)
    }
}
