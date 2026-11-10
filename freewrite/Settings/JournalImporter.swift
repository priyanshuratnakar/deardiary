//
//  JournalImporter.swift
//  Dear Diary
//
//  Brings entries across from the original freewrite app.
//
//  Dear Diary keeps its journal in its own folder, so entries written in
//  freewrite are not in it. The user picks freewrite's folder, Dear Diary says
//  what it found, and on a second click copies the entries in. It only ever
//  copies: the originals are left exactly where they are, and nothing already
//  in Dear Diary is overwritten.
//
//  Left behind on purpose: empty entries, freewrite's welcome guide, and
//  anything that is already here. Videos come with their entries.
//
//  Copied entries keep their dates. They are not sent to the AI by themselves:
//  each one is noted in `ImportRecord`, and the memory engine leaves a noted
//  entry alone until it is edited here or the user asks for a rebuild, which
//  shows the count first.
//
//  Nothing here is logged: not file names, not text.
//

import AppKit
import Combine
import Foundation

/// What was found in a folder the user picked.
struct ImportPlan: Equatable {
    struct Item: Equatable {
        /// The entry's file name, kept exactly as it is.
        let filename: String
        /// Video files that belong to it, as paths inside the journal folder.
        let videoPaths: [String]
        /// The size of everything that would be copied for this entry.
        let bytes: Int64
    }

    /// The folder the entries are in.
    let source: URL
    /// The entries to copy, oldest first.
    var items: [Item] = []
    /// Entries that are in Dear Diary already, by file name.
    var alreadyHere = 0

    var found: Int { items.count + alreadyHere }
    var videos: Int { items.filter { !$0.videoPaths.isEmpty }.count }
    var bytes: Int64 { items.map(\.bytes).reduce(0, +) }
}

enum JournalImporter {
    /// Looks in a folder for freewrite entries. It only reads; nothing is changed.
    /// If the folder holds no entries but has a "Freewrite" folder inside it, that one is used.
    static func scan(_ folder: URL, into root: URL, reader: JournalReader = JournalReader()) -> ImportPlan {
        let candidates = [folder, folder.appendingPathComponent("Freewrite", isDirectory: true)]
        let source = candidates.first { !entryFiles(in: $0).isEmpty } ?? folder
        var plan = ImportPlan(source: source)
        let manager = FileManager.default

        for url in entryFiles(in: source) {
            let filename = url.lastPathComponent
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty page and a welcome guide are not worth bringing.
            guard !trimmed.isEmpty, !reader.isWelcome(text) else { continue }

            let videoPaths = videoPaths(for: filename, in: source)
            // A video entry whose video is gone would arrive as two words and nothing else.
            if trimmed == "Video Entry" && videoPaths.isEmpty { continue }

            if manager.fileExists(atPath: root.appendingPathComponent(filename).path) {
                plan.alreadyHere += 1
                continue
            }
            let bytes = size(of: url) + videoPaths.map { size(of: source.appendingPathComponent($0)) }.reduce(0, +)
            plan.items.append(ImportPlan.Item(filename: filename, videoPaths: videoPaths, bytes: bytes))
        }
        // File names start with a random id, so order by the date in the name instead.
        plan.items.sort { (date(in: $0.filename), $0.filename) < (date(in: $1.filename), $1.filename) }
        return plan
    }

    /// Copies one entry, with its video if it has one. Nothing that already exists is replaced.
    static func copy(_ item: ImportPlan.Item, from source: URL, into root: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        // The video first, so an entry never arrives without it.
        for path in item.videoPaths {
            let destination = root.appendingPathComponent(path)
            guard !manager.fileExists(atPath: destination.path) else { continue }
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source.appendingPathComponent(path), to: destination)
        }

        let destination = root.appendingPathComponent(item.filename)
        guard !manager.fileExists(atPath: destination.path) else { return }
        try manager.copyItem(at: source.appendingPathComponent(item.filename), to: destination)
    }

    // MARK: - Looking

    /// Files named like freewrite entries: "[UUID]-[yyyy-MM-dd-HH-mm-ss].md".
    private static func entryFiles(in folder: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.filter { JournalReader.parse(filename: $0.lastPathComponent) != nil }
    }

    private static func date(in filename: String) -> Date {
        JournalReader.parse(filename: filename)?.startedAt ?? .distantPast
    }

    /// Where freewrite has kept an entry's video over the years: in its own folder under
    /// Videos, loose under Videos, or beside the entry.
    private static func videoPaths(for filename: String, in source: URL) -> [String] {
        let base = String(filename.dropLast(".md".count))
        let candidates = ["Videos/\(base)", "Videos/\(base).mov", "\(base).mov"]
        return candidates.filter { FileManager.default.fileExists(atPath: source.appendingPathComponent($0).path) }
    }

    /// The size of a file, or of everything inside a folder.
    private static func size(of url: URL) -> Int64 {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return ((try? manager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        }
        var total: Int64 = 0
        for case let file as URL in manager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) ?? FileManager.DirectoryEnumerator() {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}

/// Which entries were copied in from freewrite, and when.
///
/// The memory engine asks this before it reads an entry. An entry that was copied in
/// waits for "Rebuild memory" like any entry from before memory was switched on, even
/// if it was edited in freewrite after that moment. Once it is edited here, it is
/// treated like any other entry.
///
/// Kept in UserDefaults as entry ids and times. No names and no text.
final class ImportRecord: @unchecked Sendable {
    /// The app's record. Under test it is a throwaway copy.
    static let shared: ImportRecord = {
        guard StorageRoot.isRunningTests() else {
            return ImportRecord()
        }
        return ImportRecord(defaults: UserDefaults(suiteName: "deardiary.tests.host.import.\(UUID().uuidString)") ?? .standard)
    }()

    private static let key = "import.broughtIn"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var times: [String: Double]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.times = (defaults.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
    }

    /// Notes that these entries were copied in at this moment.
    func note(_ ids: [UUID], at date: Date) {
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for id in ids {
            times[id.uuidString] = date.timeIntervalSince1970
        }
        defaults.set(times, forKey: Self.key)
    }

    /// When an entry was copied in, or nil if it was written here.
    func date(for id: UUID) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return times[id.uuidString].map { Date(timeIntervalSince1970: $0) }
    }
}

/// What the "Bring entries from freewrite…" section in Settings is doing.
@MainActor
final class JournalImport: ObservableObject {
    enum State: Equatable {
        case idle
        /// A folder was picked and it has entries that are not here yet.
        case found(ImportPlan)
        /// A folder was picked, and every entry in it is here already.
        case allHere(Int)
        /// A folder was picked and it holds no freewrite entries.
        case nothing
        case copying(done: Int, total: Int)
        case done(copied: Int, total: Int, failed: Int)
    }

    static let shared = JournalImport()

    @Published private(set) var state: State = .idle
    /// Fires when entries have been copied in, so the page can show them in History.
    let didCopy = PassthroughSubject<Void, Never>()

    private let root: URL
    private let reader: JournalReader
    private let record: ImportRecord
    private let now: () -> Date
    private let pickFolder: () async -> URL?
    private var copyTask: Task<Void, Never>? = nil

    init(
        root: URL = StorageRoot.url,
        reader: JournalReader = JournalReader(),
        record: ImportRecord = .shared,
        now: @escaping () -> Date = { Date() },
        pickFolder: @escaping () async -> URL? = JournalImport.pickFolderWithPanel
    ) {
        self.root = root
        self.reader = reader
        self.record = record
        self.now = now
        self.pickFolder = pickFolder
    }

    /// True while nothing is under way, so the word in Settings can be clicked.
    var canChoose: Bool {
        switch state {
        case .idle, .nothing, .allHere, .done: return true
        case .found, .copying: return false
        }
    }

    /// Asks for freewrite's folder and looks at what is in it.
    func choose() async {
        guard canChoose, let folder = await pickFolder() else { return }
        let root = self.root
        let reader = self.reader
        let plan = await Task.detached(priority: .userInitiated) {
            JournalImporter.scan(folder, into: root, reader: reader)
        }.value

        if !plan.items.isEmpty {
            state = .found(plan)
        } else if plan.alreadyHere > 0 {
            state = .allHere(plan.alreadyHere)
        } else {
            state = .nothing
        }
    }

    /// Copies what was found, one entry at a time, off the main thread.
    func copy() {
        guard case .found(let plan) = state else { return }
        let root = self.root
        let record = self.record
        let now = self.now
        state = .copying(done: 0, total: plan.items.count)

        // Noted before the first file lands, so memory never meets a copied entry it has not been told about.
        record.note(plan.items.compactMap { JournalReader.parse(filename: $0.filename)?.id }, at: now())

        copyTask = Task { [weak self] in
            var copied: [UUID] = []
            var failed = 0
            for item in plan.items {
                if Task.isCancelled { break }
                let worked = await Task.detached(priority: .utility) {
                    (try? JournalImporter.copy(item, from: plan.source, into: root)) != nil
                }.value
                if worked, let id = JournalReader.parse(filename: item.filename)?.id {
                    copied.append(id)
                } else {
                    failed += 1
                }
                guard let self else { return }
                if !Task.isCancelled {
                    self.state = .copying(done: copied.count + failed, total: plan.items.count)
                }
            }
            // Noted again now that they are here, in case a copy did not keep its file's date.
            record.note(copied, at: now())

            guard let self else { return }
            if copied.isEmpty && failed == 0 {
                // Stopped before the first entry: nothing happened.
                self.state = .idle
                return
            }
            self.state = .done(copied: copied.count, total: plan.items.count, failed: failed)
            if !copied.isEmpty {
                self.didCopy.send()
            }
        }
    }

    /// Stops after the entry being copied. What has been copied stays.
    func stop() {
        copyTask?.cancel()
    }

    /// Backs out before anything is copied.
    func cancel() {
        guard case .found = state else { return }
        state = .idle
    }

    /// For tests and pictures: show this state.
    func show(_ state: State) {
        self.state = state
    }

    /// For tests: waits until copying has finished.
    func waitUntilCopied() async {
        await copyTask?.value
    }

    // MARK: - What Settings says

    /// The line under the description, or nil when there is nothing to say yet.
    var line: String? {
        switch state {
        case .idle:
            return nil
        case .found(let plan):
            var text = "Found \(Self.entries(plan.found))"
            if plan.videos > 0 {
                text += " and \(plan.videos) \(plan.videos == 1 ? "video" : "videos")"
            }
            text += " (\(Self.size(plan.bytes)))."
            if plan.alreadyHere > 0 {
                text += " \(plan.alreadyHere) \(plan.alreadyHere == 1 ? "is" : "are") already here."
            }
            return text
        case .allHere(let count):
            return count == 1
                ? "Found 1 entry. It is already here."
                : "Found \(count) entries. All of them are already here."
        case .nothing:
            return "No freewrite entries in that folder. The folder is usually called Freewrite."
        case .copying(let done, let total):
            return "Copying \(min(done + 1, total)) of \(total)…"
        case .done(let copied, let total, let failed):
            guard copied > 0 else {
                return "Couldn't copy the entries. Nothing was changed."
            }
            var text = copied == total
                ? "Copied \(Self.entries(copied))."
                : "Copied \(copied) of \(Self.entries(total))."
            text += copied == 1 ? " It is in History now." : " They are in History now."
            if failed > 0 {
                text += " \(failed) could not be copied."
            }
            return text
        }
    }

    /// The word that starts the copy.
    var copyWord: String? {
        guard case .found(let plan) = state else { return nil }
        return "Copy \(Self.entries(plan.items.count))"
    }

    private static func entries(_ count: Int) -> String {
        "\(count) \(count == 1 ? "entry" : "entries")"
    }

    private static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(bytes, 1024))
    }

    // MARK: - Picking the folder

    /// The macOS folder picker. It opens where freewrite usually keeps its entries.
    static func pickFolderWithPanel() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder freewrite keeps your entries in. It is usually called Freewrite."
        panel.prompt = "Choose"
        panel.directoryURL = usualFreewriteFolder()
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    /// Where the original app keeps its journal. Dear Diary cannot look there itself:
    /// this is only where the picker starts, and the user chooses.
    private static func usualFreewriteFolder() -> URL? {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Containers/app.humansongs.freewrite/Data/Documents", isDirectory: true)
    }
}
