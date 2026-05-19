import Foundation

final class LibraryStore {
    static let shared = LibraryStore()

    struct Snapshot: Codable {
        let folderURL: URL?
        let songs: [Song]
    }

    private let fileURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("myTunes", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    var storagePath: String { fileURL.path }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
