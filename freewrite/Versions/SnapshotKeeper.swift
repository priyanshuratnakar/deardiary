//
//  SnapshotKeeper.swift
//  Dear Diary
//
//  Keeps versions in the background.
//
//  Like the memory engine, it looks at the journal folder itself, once a
//  minute, off the main thread. It reads the files freewrite has already
//  saved, so it never touches the page and typing never waits for it. While
//  versions are off each check returns at once without reading anything.
//
//  A version of an entry is saved when:
//    - its text is different from its newest version, and
//    - five minutes have passed since that version (or, for an entry with no
//      version yet, since the entry was started).
//  The entry as it is right now is also kept just before a restore, so a
//  restore can always be undone.
//
//  Empty entries, video entries and freewrite's welcome guide are skipped.
//  The newest 50 versions of each entry are kept.
//

import Foundation
import Combine

struct VersionLimits {
    /// At least this long between two versions of one entry.
    var spacing: TimeInterval = 300
    /// How many versions of each entry are kept. Older ones are removed.
    var keep = 50
    /// How often the journal folder is checked.
    var passInterval: TimeInterval = 60
}

/// Everything the keeper depends on. Tests swap in throwaway versions.
struct VersionEnvironment {
    var isEnabled: () -> Bool
    var store: SnapshotStore
    var journal: JournalReader
    var now: () -> Date
    var limits = VersionLimits()

    static var live: VersionEnvironment {
        let settings = VersionSettings.shared
        return VersionEnvironment(
            isEnabled: { settings.isOn() },
            store: SnapshotStore(),
            journal: JournalReader(),
            now: { Date() }
        )
    }
}

/// What the rest of the app can see about versions. Published on the main thread.
final class VersionIndex: ObservableObject, @unchecked Sendable {
    /// The entries that have an earlier version worth opening.
    @Published var entries: Set<UUID> = []
    /// A plain sentence when versions could not be saved, otherwise nil.
    @Published var problem: String? = nil
}

actor SnapshotKeeper {
    static let shared = SnapshotKeeper(environment: .live)

    nonisolated let index = VersionIndex()

    private let env: VersionEnvironment
    private var loop: Task<Void, Never>? = nil
    /// Entries that were read and needed no version, with the time they were last
    /// saved, so an unchanged file is not read again every minute.
    private var looked: [UUID: Date] = [:]

    init(environment: VersionEnvironment) {
        self.env = environment
    }

    // MARK: - Starting and nudging

    /// Starts checking the journal folder once a minute. Called once at launch.
    nonisolated func start() {
        Task { await self.beginLoop() }
    }

    private func beginLoop() {
        guard loop == nil else { return }
        let interval = env.limits.passInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runPass()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Asks for a check now (used when versions are switched on or off in Settings).
    nonisolated func nudge() {
        Task { await self.runPass() }
    }

    // MARK: - One look at the journal folder

    /// Saves a version of every entry that is due one. Returns how many were saved.
    @discardableResult
    func runPass() async -> Int {
        guard env.isEnabled() else {
            looked = [:]
            await publish(entries: [], problem: nil)
            return 0
        }
        guard let files = env.journal.entryFiles() else {
            return 0
        }

        let now = env.now()
        let known = env.store.newestByEntry()
        var worthOpening: Set<UUID> = []
        var problem: String? = nil
        var saved = 0

        for file in files {
            let latest = known[file.id]

            // An entry is worth opening when it has a version that differs from how it
            // reads now: more than one version, or one version and an edit since.
            if let latest, latest.count >= 2 || file.modifiedAt > latest.newest.savedAt {
                worthOpening.insert(file.id)
            }

            // Nothing has been written since the newest version.
            if let latest, file.modifiedAt <= latest.newest.savedAt {
                continue
            }
            // Too soon after the last version, or after the entry was started.
            let since = latest?.newest.savedAt ?? file.startedAt
            guard now.timeIntervalSince(since) >= env.limits.spacing else {
                continue
            }
            // Already read as it stands, and it needed no version.
            if looked[file.id] == file.modifiedAt {
                continue
            }

            guard let text = env.journal.text(of: file), env.journal.isDigestible(text, file: file) else {
                looked[file.id] = file.modifiedAt
                continue
            }
            if let latest, env.store.text(of: latest.newest) == text {
                looked[file.id] = file.modifiedAt
                continue
            }

            do {
                try env.store.save(text, for: file.id, at: now)
                env.store.trim(file.id, keeping: env.limits.keep)
                saved += 1
                if latest != nil {
                    worthOpening.insert(file.id)
                }
            } catch {
                problem = "Couldn't save versions to the journal folder."
            }
        }

        // Forget what was noted about entries that are gone.
        let present = Set(files.map(\.id))
        looked = looked.filter { present.contains($0.key) }

        await publish(entries: worthOpening.intersection(present), problem: problem)
        return saved
    }

    // MARK: - Restoring and deleting

    /// Keeps the entry as it reads now, just before a restore replaces it.
    /// Returns false if it could not be kept, in which case nothing should be restored.
    func keep(_ text: String, for entryID: UUID) async -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // An empty page has nothing to lose.
            return true
        }
        if let newest = env.store.versions(of: entryID).first, env.store.text(of: newest) == text {
            return true
        }
        do {
            try env.store.save(text, for: entryID, at: env.now())
            env.store.trim(entryID, keeping: env.limits.keep)
            return true
        } catch {
            return false
        }
    }

    /// An entry was deleted: its versions go with it.
    nonisolated func entryDeleted(_ entryID: UUID) {
        Task { await self.forget(entryID) }
    }

    func forget(_ entryID: UUID) async {
        env.store.deleteAll(for: entryID)
        looked[entryID] = nil
        let index = self.index
        await MainActor.run {
            if index.entries.contains(entryID) {
                index.entries.remove(entryID)
            }
        }
    }

    private func publish(entries: Set<UUID>, problem: String?) async {
        let index = self.index
        await MainActor.run {
            if index.entries != entries {
                index.entries = entries
            }
            if index.problem != problem {
                index.problem = problem
            }
        }
    }
}
