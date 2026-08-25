import Foundation
import CoreData
import Combine

@MainActor
public final class NoteStore: NSObject, ObservableObject {
    @Published public var notes: [Note] = []

    private let persistence: PersistenceController
    private var fetchedResultsController: NSFetchedResultsController<NoteEntity>!

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        super.init()
        setupFetchedResultsController()
        fetchNotes()
    }

    private func setupFetchedResultsController() {
        let request = NoteEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: persistence.container.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        fetchedResultsController.delegate = self

        do {
            try fetchedResultsController.performFetch()
        } catch {
            print("Failed to perform initial fetch: \(error)")
        }
    }

    public func fetchNotes() {
        notes = (fetchedResultsController.fetchedObjects ?? []).map { $0.toNote() }
    }

    public func addNote(_ note: Note) {
        let context = persistence.container.viewContext
        let entity = NoteEntity(context: context)
        entity.apply(from: note)
        if let fileName = note.audioFileName {
            entity.audioAsset = AudioFileStore.shared.readData(fileName: fileName)
        }
        persistence.saveContext()
    }

    public func updateNote(_ note: Note) {
        let context = persistence.container.viewContext
        let request = NoteEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", note.id as CVarArg)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return }
        var updated = note
        updated.modifiedDate = Date()
        entity.apply(from: updated)
        persistence.saveContext()
    }

    public func deleteNote(_ note: Note) {
        let context = persistence.container.viewContext
        let request = NoteEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", note.id as CVarArg)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return }
        if let fileName = entity.audioFileName {
            AudioFileStore.shared.delete(fileName: fileName)
        }
        context.delete(entity)
        persistence.saveContext()
    }

    public func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            deleteNote(notes[index])
        }
    }
}

extension NoteStore: NSFetchedResultsControllerDelegate {
    public nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            self.fetchNotes()
        }
    }
}
