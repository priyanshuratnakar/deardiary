//
//  JournalReader.swift
//  Dear Diary
//
//  Lets the memory engine look at the journal folder without going through
//  ContentView. It only ever reads: entries are never changed from here.
//

import Foundation

/// One entry file in the journal folder.
struct JournalEntryFile: Equatable {
    let id: UUID
    /// When the entry was started, taken from its file name.
    let startedAt: Date
    let url: URL
    /// When it was last saved. freewrite saves on every keystroke, so this is the last edit.
    let modifiedAt: Date
}

struct JournalReader {
    /// The journal folder. Tests pass a throwaway folder.
    let root: URL
    /// The welcome page a new journal starts with. It is not the user's writing, so it is never digested.
    let welcomeText: String?
    /// Welcome pages from before (freewrite's own guide), which a journal may still hold.
    let earlierWelcomeTexts: [String]

    init(
        root: URL = StorageRoot.url,
        welcomeText: String? = JournalReader.bundledWelcomeText(),
        earlierWelcomeTexts: [String] = JournalReader.bundledEarlierWelcomeTexts()
    ) {
        self.root = root
        self.welcomeText = welcomeText
        self.earlierWelcomeTexts = earlierWelcomeTexts
    }

    /// Dear Diary's welcome page.
    static func bundledWelcomeText() -> String? {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Welcome pages from before: freewrite's guide, which Dear Diary used before it had its
    /// own, and earlier wordings of Dear Diary's own. A journal that opened on one of them
    /// still holds it, and it is still not the user's writing.
    static func bundledEarlierWelcomeTexts() -> [String] {
        ["freewrite-welcome", "dear-diary-welcome-1"].compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "md") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    /// True if this is a welcome page, now or from before, rather than the user's own writing.
    func isWelcome(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return ([welcomeText].compactMap { $0 } + earlierWelcomeTexts).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }
    }

    /// Every entry in the journal folder, oldest first.
    /// Returns nil if the folder could not be read, which is different from "no entries".
    func entryFiles() -> [JournalEntryFile]? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else {
            return nil
        }

        let files = urls.compactMap { url -> JournalEntryFile? in
            guard let parsed = Self.parse(filename: url.lastPathComponent),
                  let modified = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate else {
                return nil
            }
            return JournalEntryFile(id: parsed.id, startedAt: parsed.startedAt, url: url, modifiedAt: modified)
        }
        return files.sorted {
            ($0.startedAt, $0.url.lastPathComponent) < ($1.startedAt, $1.url.lastPathComponent)
        }
    }

    func text(of file: JournalEntryFile) -> String? {
        try? String(contentsOf: file.url, encoding: .utf8)
    }

    /// True if this is the user's own writing: not empty, not a video entry, not the welcome guide.
    func isDigestible(_ text: String, file: JournalEntryFile) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Video Entry", !hasVideo(file) else {
            return false
        }
        return !isWelcome(text)
    }

    /// Video entries keep a .mov beside (or, in older layouts, near) their .md file.
    private func hasVideo(_ file: JournalEntryFile) -> Bool {
        let base = file.url.deletingPathExtension().lastPathComponent
        let videos = root.appendingPathComponent("Videos", isDirectory: true)
        let candidates = [
            videos.appendingPathComponent(base, isDirectory: true).appendingPathComponent("\(base).mov"),
            videos.appendingPathComponent("\(base).mov"),
            root.appendingPathComponent("\(base).mov"),
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Reads "[UUID]-[yyyy-MM-dd-HH-mm-ss].md". Anything else is not an entry.
    static func parse(filename: String) -> (id: UUID, startedAt: Date)? {
        guard filename.hasPrefix("["),
              filename.hasSuffix("].md"),
              let divider = filename.range(of: "]-[") else {
            return nil
        }
        let idText = filename[filename.index(after: filename.startIndex)..<divider.lowerBound]
        let stamp = filename[divider.upperBound..<filename.index(filename.endIndex, offsetBy: -4)]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"

        guard let id = UUID(uuidString: String(idText)),
              let startedAt = formatter.date(from: String(stamp)) else {
            return nil
        }
        return (id, startedAt)
    }
}
