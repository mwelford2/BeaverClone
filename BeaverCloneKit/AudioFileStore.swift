import Foundation

public final class AudioFileStore {
    public static let shared = AudioFileStore()

    private init() {}

    public var directory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public func newRecordingURL() -> URL {
        let fileName = "\(UUID().uuidString).m4a"
        return url(for: fileName)
    }

    public func readData(fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    public func write(data: Data, fileName: String) {
        try? data.write(to: url(for: fileName))
    }

    public func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// Ensures a CloudKit-synced audio blob (received on another device) is materialized as a local file.
    public func materialize(data: Data?, fileName: String?) {
        guard let data, let fileName else { return }
        let destination = url(for: fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? data.write(to: destination)
        }
    }
}
