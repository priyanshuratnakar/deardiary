//
//  MemoryStore.swift
//  Dear Diary
//
//  Reads and writes the memory folder. Nothing else touches these files.
//
//      <journal folder>/memory/
//        profile.md              a short running picture, rewritten as things change
//        thoughts/<id>.md        one readable note per thought
//        entries/<UUID>.json     one digest per entry, with a fingerprint of its text
//        pins.json               the user's manual fixes (read here, written in M6)
//
//  Deleting the memory folder loses nothing the user wrote.
//

import Foundation

struct MemoryStore {
    /// The journal folder. Tests pass a throwaway folder.
    let root: URL

    init(root: URL = StorageRoot.url) {
        self.root = root
    }

    var folder: URL { root.appendingPathComponent("memory", isDirectory: true) }
    var thoughtsFolder: URL { folder.appendingPathComponent("thoughts", isDirectory: true) }
    var entriesFolder: URL { folder.appendingPathComponent("entries", isDirectory: true) }
    var profileURL: URL { folder.appendingPathComponent("profile.md") }
    var pinsURL: URL { folder.appendingPathComponent("pins.json") }

    func thoughtURL(_ id: String) -> URL {
        thoughtsFolder.appendingPathComponent("\(id).md")
    }

    func digestURL(_ entryID: UUID) -> URL {
        entriesFolder.appendingPathComponent("\(entryID.uuidString).json")
    }

    private var fileManager: FileManager { .default }

    // MARK: - Thoughts and profile

    /// Everything the AI has built so far. Notes that cannot be read are skipped,
    /// and remembered so they are never overwritten.
    func loadSnapshot() -> MemorySnapshot {
        var snapshot = MemorySnapshot()

        let files = (try? fileManager.contentsOfDirectory(at: thoughtsFolder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "md" {
            let id = file.deletingPathExtension().lastPathComponent
            if let content = try? String(contentsOf: file, encoding: .utf8),
               let thought = ThoughtNote.parse(content, id: id) {
                snapshot.thoughts[id] = thought
            } else {
                snapshot.unreadableIDs.insert(id)
            }
        }

        if let profile = try? String(contentsOf: profileURL, encoding: .utf8) {
            snapshot.profile = Self.profileText(fromFile: profile)
        }
        return snapshot
    }

    /// Writes what changed between two snapshots: new and changed notes are saved,
    /// notes that are gone are removed, and the profile is rewritten if it differs.
    func write(_ new: MemorySnapshot, replacing old: MemorySnapshot) throws {
        try fileManager.createDirectory(at: thoughtsFolder, withIntermediateDirectories: true)

        for (id, thought) in new.thoughts where old.thoughts[id] != thought {
            guard !new.unreadableIDs.contains(id) else { continue }
            try ThoughtNote.render(thought).write(to: thoughtURL(id), atomically: true, encoding: .utf8)
        }
        for id in old.thoughts.keys where new.thoughts[id] == nil {
            guard !new.unreadableIDs.contains(id) else { continue }
            let url = thoughtURL(id)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        if new.profile != old.profile {
            try Self.profileFile(from: new.profile).write(to: profileURL, atomically: true, encoding: .utf8)
        }
    }

    private static let profileTitle = "# Profile"

    private static func profileFile(from text: String) -> String {
        "\(profileTitle)\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
    }

    private static func profileText(fromFile content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(profileTitle) {
            text = String(text.dropFirst(profileTitle.count))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Entry digests

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func loadDigest(entryID: UUID) -> EntryDigest? {
        guard let data = try? Data(contentsOf: digestURL(entryID)) else { return nil }
        return try? Self.decoder().decode(EntryDigest.self, from: data)
    }

    func loadAllDigests() -> [EntryDigest] {
        let files = (try? fileManager.contentsOfDirectory(at: entriesFolder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? Self.decoder().decode(EntryDigest.self, from: $0) }
    }

    func saveDigest(_ digest: EntryDigest) throws {
        try fileManager.createDirectory(at: entriesFolder, withIntermediateDirectories: true)
        try Self.encoder().encode(digest).write(to: digestURL(digest.entryID), options: .atomic)
    }

    func deleteDigest(entryID: UUID) {
        try? fileManager.removeItem(at: digestURL(entryID))
    }

    // MARK: - The user's fixes

    /// The user's manual fixes. A missing or unreadable file means no fixes.
    func loadPins() -> Pins {
        guard let data = try? Data(contentsOf: pinsURL),
              let pins = try? JSONDecoder().decode(Pins.self, from: data) else {
            return Pins()
        }
        return pins
    }

    /// Writes the user's fixes. With no fixes left, the file is removed.
    func savePins(_ pins: Pins) throws {
        guard !pins.isEmpty else {
            if fileManager.fileExists(atPath: pinsURL.path) {
                try fileManager.removeItem(at: pinsURL)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(pins).write(to: pinsURL, options: .atomic)
    }

    // MARK: - Forgetting

    /// Removes everything the AI built but keeps the user's fixes, and keeps any
    /// note that cannot be read (it may be a hand edit). Used before a rebuild.
    func forgetAIBuilt() {
        let snapshot = loadSnapshot()
        for id in snapshot.thoughts.keys {
            try? fileManager.removeItem(at: thoughtURL(id))
        }
        try? fileManager.removeItem(at: entriesFolder)
        try? fileManager.removeItem(at: profileURL)
    }

    /// Removes the whole memory folder, fixes included. Entries are not touched.
    func forgetEverything() {
        try? fileManager.removeItem(at: folder)
    }

    /// Makes sure the folder exists (so it can be opened in Finder) and returns it.
    @discardableResult
    func ensureFolder() -> URL {
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
