//
//  SnapshotStore.swift
//  Dear Diary
//
//  Reads and writes the versions folder: timed copies of each entry, so an
//  earlier state of an entry can be read and brought back.
//
//  On disk, inside the journal folder:
//
//      versions/[ENTRY-UUID]/[yyyy-MM-dd-HH-mm-ss].md
//
//  Each file is the entry's text exactly as it was at that time. They are
//  plain text and can be opened, copied or deleted by hand.
//

import Foundation

/// One saved copy of an entry.
struct EntryVersion: Equatable, Identifiable {
    let entryID: UUID
    /// When the copy was saved, taken from its file name.
    let savedAt: Date
    let url: URL

    var id: String { url.lastPathComponent }
}

struct SnapshotStore {
    /// The journal folder. Tests pass a throwaway folder.
    let root: URL

    init(root: URL = StorageRoot.url) {
        self.root = root
    }

    var folder: URL {
        root.appendingPathComponent("versions", isDirectory: true)
    }

    func folder(for entryID: UUID) -> URL {
        folder.appendingPathComponent("[\(entryID.uuidString)]", isDirectory: true)
    }

    // MARK: - File names

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }

    static func filename(for date: Date) -> String {
        "[\(formatter().string(from: date))].md"
    }

    /// Reads "[yyyy-MM-dd-HH-mm-ss].md". Anything else is not a version.
    static func date(fromFilename name: String) -> Date? {
        guard name.hasPrefix("["), name.hasSuffix("].md") else { return nil }
        return formatter().date(from: String(name.dropFirst().dropLast(4)))
    }

    // MARK: - Reading

    /// Every version of an entry, newest first.
    func versions(of entryID: UUID) -> [EntryVersion] {
        let directory = folder(for: entryID)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names
            .compactMap { name in
                Self.date(fromFilename: name).map {
                    EntryVersion(entryID: entryID, savedAt: $0, url: directory.appendingPathComponent(name))
                }
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// For every entry that has versions: how many, and the newest one.
    func newestByEntry() -> [UUID: (count: Int, newest: EntryVersion)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return [:]
        }
        var result: [UUID: (count: Int, newest: EntryVersion)] = [:]
        for name in names {
            guard name.hasPrefix("["), name.hasSuffix("]"),
                  let id = UUID(uuidString: String(name.dropFirst().dropLast())) else {
                continue
            }
            let all = versions(of: id)
            if let newest = all.first {
                result[id] = (all.count, newest)
            }
        }
        return result
    }

    func text(of version: EntryVersion) -> String? {
        try? String(contentsOf: version.url, encoding: .utf8)
    }

    // MARK: - Writing

    /// Saves a copy of an entry's text.
    @discardableResult
    func save(_ text: String, for entryID: UUID, at date: Date) throws -> EntryVersion {
        let directory = folder(for: entryID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // File names are to the second. If one is taken, the next free second is used.
        var stamp = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        var url = directory.appendingPathComponent(Self.filename(for: stamp))
        while FileManager.default.fileExists(atPath: url.path) {
            stamp = stamp.addingTimeInterval(1)
            url = directory.appendingPathComponent(Self.filename(for: stamp))
        }

        try text.write(to: url, atomically: true, encoding: .utf8)
        return EntryVersion(entryID: entryID, savedAt: stamp, url: url)
    }

    /// Keeps the newest versions of an entry and removes the rest.
    func trim(_ entryID: UUID, keeping limit: Int) {
        for version in versions(of: entryID).dropFirst(max(limit, 1)) {
            try? FileManager.default.removeItem(at: version.url)
        }
    }

    /// Removes every version of an entry.
    func deleteAll(for entryID: UUID) {
        try? FileManager.default.removeItem(at: folder(for: entryID))
    }

    /// Makes sure the versions folder exists and returns it, for "Open versions folder".
    @discardableResult
    func ensureFolder() -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
