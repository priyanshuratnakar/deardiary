//
//  MemoryEngine.swift
//  Dear Diary
//
//  Builds memory in the background, one settled entry at a time.
//
//  It runs off the main thread and never touches the page. It looks at the
//  journal folder itself, so ContentView does not need to tell it anything.
//  Nothing is sent unless AI is on, memory is on, and a key is saved.
//
//  An entry is digested when it has settled:
//    - it has not been edited for 10 minutes, or
//    - a newer entry exists, or
//    - the day has changed, or
//    - talk was just switched on.
//  It is never digested while it is being typed (edited in the last minute).
//
//  Each digest stores a fingerprint of the entry text, so an unchanged entry
//  is never sent twice. Failures are quiet: they show as one line in Settings
//  and are tried again later.
//

import Foundation
import CryptoKit
import Combine

/// What Settings shows about memory.
struct MemorySummary: Equatable {
    var thoughts = 0
    var digestedEntries = 0
    /// Entries that have changed or are new, and are waiting to settle or to be sent.
    var waitingEntries = 0
    var isWorking = false
    var workDone = 0
    var workTotal = 0
    var lastUpdated: Date? = nil
    /// A plain sentence when something went wrong, otherwise nil.
    var problem: String? = nil
    /// What the last weekly tidy did, in one line, or nil if there has not been one.
    var lastTidy: String? = nil
}

/// Published on the main thread for the Settings window.
final class MemoryStatus: ObservableObject, @unchecked Sendable {
    @Published var summary = MemorySummary()
}

struct MemoryLimits {
    /// An entry edited more recently than this is treated as being typed.
    var typingGuard: TimeInterval = 60
    /// An entry left alone for this long has settled.
    var settleAfter: TimeInterval = 600
    /// A ceiling on background requests in one day, as a guard against runaway cost.
    var dailyRequests = 40
    /// After a failure, wait this long before trying again.
    var retryGap: TimeInterval = 300
    /// How often the journal folder is checked.
    var passInterval: TimeInterval = 60
    /// How long after one tidy the next one is due.
    var tidyEvery: TimeInterval = 7 * 24 * 3600
    /// The weekly tidy waits until memory holds at least this many thoughts.
    var tidyMinimumThoughts = 8
    /// A rebuild ends with a tidy, so duplicates merged earlier do not come back.
    var tidyAfterRebuild = true
    /// A thought seen in one entry can be retired once that entry is this many days old.
    var oneOffAfterDays = 21
}

/// Everything the engine depends on. Tests swap in throwaway versions.
struct MemoryEnvironment {
    var isEnabled: () -> Bool
    var enabledSince: () -> Date?
    var model: () -> String
    var store: MemoryStore
    var journal: JournalReader
    var provider: () -> LLMProvider
    /// Which service is in use, so a problem can be reported in its name.
    var service: () -> AIProviderKind = { .claude }
    /// When an entry was copied in from freewrite, or nil if it was written here.
    var broughtInAt: (UUID) -> Date? = { _ in nil }
    var now: () -> Date
    var defaults: UserDefaults
    var limits = MemoryLimits()

    static var live: MemoryEnvironment {
        let settings = AISettings.shared
        return MemoryEnvironment(
            isEnabled: { settings.memoryAllowed() },
            enabledSince: { settings.memoryEnabledSince() },
            model: { settings.savedDigestModel() },
            store: MemoryStore(),
            journal: JournalReader(),
            provider: { AIRouter.shared },
            service: { settings.savedProvider() },
            broughtInAt: { ImportRecord.shared.date(for: $0) },
            now: { Date() },
            defaults: .standard
        )
    }
}

actor MemoryEngine {
    static let shared = MemoryEngine(environment: .live)

    nonisolated let status = MemoryStatus()

    enum PassOutcome: Equatable {
        /// Memory is off, AI is off, or there is no key. Nothing was read or sent.
        case off
        /// Another pass is already running.
        case busy
        /// Waiting a while after a failure.
        case paused
        /// The journal folder could not be read.
        case unreadable
        case finished(digested: Int)
    }

    private let env: MemoryEnvironment
    private var isRunning = false
    private var stopRequested = false
    private var pausedUntil: Date? = nil
    private var summary = MemorySummary()
    private var loop: Task<Void, Never>? = nil
    /// Fingerprints of entries already read, so unchanged files are not read again every minute.
    private var fingerprints: [UUID: (modifiedAt: Date, hash: String)] = [:]

    init(environment: MemoryEnvironment) {
        self.env = environment
    }

    // MARK: - Starting, nudging, stopping

    /// Starts checking the journal folder once a minute. Called once at launch.
    /// While memory is off each check returns at once without reading or sending anything.
    nonisolated func start() {
        Task { await self.beginLoop() }
    }

    private func beginLoop() {
        guard loop == nil else { return }
        let interval = env.limits.passInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if case .finished = await self?.runPass() {
                    // About once a week, with nothing else to do, look across all of memory.
                    await self?.tidy()
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Asks for a check now. With `includeFresh`, an entry that was typed more than
    /// a minute ago counts as settled (used when talk is switched on).
    nonisolated func nudge(includeFresh: Bool = false) {
        Task { await self.runPass(includeFresh: includeFresh) }
    }

    /// Stops after the entry being worked on.
    func stop() {
        stopRequested = true
    }

    private func waitUntilIdle() async {
        stopRequested = true
        while isRunning {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Rebuild and forget

    /// How many entries a rebuild would send. Shown before the user confirms.
    func entriesToRebuild() -> Int {
        guard let files = env.journal.entryFiles() else { return 0 }
        return files.filter { file in
            guard let text = env.journal.text(of: file) else { return false }
            return env.journal.isDigestible(text, file: file)
        }.count
    }

    /// Throws away what the AI built (the user's fixes are kept) and digests every entry again.
    func rebuild() async {
        guard env.isEnabled() else { return }
        await waitUntilIdle()
        env.store.forgetAIBuilt()
        fingerprints = [:]
        pausedUntil = nil
        summary = MemorySummary()
        await runPass(everything: true)
        if env.limits.tidyAfterRebuild, !stopRequested {
            await tidy(force: true)
        }
    }

    /// Deletes the whole memory folder. Entries are not touched.
    func forgetEverything() async {
        await waitUntilIdle()
        env.store.forgetEverything()
        fingerprints = [:]
        pausedUntil = nil
        env.defaults.removeObject(forKey: TidyKey.at)
        env.defaults.removeObject(forKey: TidyKey.line)
        summary = MemorySummary()
        await publish()
    }

    /// Recounts what is in the memory folder, for Settings. Reads local files only.
    func refreshStatus() async {
        guard !isRunning else { return }
        summary.thoughts = env.store.loadSnapshot().thoughts.count
        summary.digestedEntries = env.store.loadAllDigests().filter { !$0.failed }.count
        summary.lastTidy = env.defaults.string(forKey: TidyKey.line)
        await publish()
    }

    // MARK: - The user's fixes

    /// Makes one of the user's fixes: changes the notes and records it in the fixes file.
    /// This needs no AI and works whether memory is on or off. It runs here, in
    /// the engine, so it can never collide with a digest being written.
    @discardableResult
    func fix(_ fix: MemoryFix) async -> Bool {
        let before = env.store.loadSnapshot()
        var memory = before
        var pins = env.store.loadPins()
        guard MemoryFixes.apply(fix, to: &memory, pins: &pins) else {
            return false
        }
        do {
            // The fixes file first: if the notes could not be written, the fix is
            // still on record and is applied the next time memory changes.
            try env.store.savePins(pins)
            try env.store.write(memory, replacing: before)
        } catch {
            summary.problem = "Couldn't write to the memory folder."
            await publish()
            return false
        }
        summary.thoughts = memory.thoughts.count
        summary.lastUpdated = env.now()
        await publish()
        return true
    }

    // MARK: - The weekly tidy

    private enum TidyKey {
        static let at = "memory.tidy.at"
        static let line = "memory.tidy.line"
    }

    /// Looks across all of memory: merges duplicates, retires one-offs, adds patterns
    /// that only show across weeks, and refreshes the profile. One request.
    ///
    /// Without `force` it only runs when a week has passed since the last tidy and
    /// memory holds enough thoughts to be worth it. Returns nil if it did not run.
    @discardableResult
    func tidy(force: Bool = false) async -> MemoryTidier.Outcome? {
        guard env.isEnabled(), !isRunning else {
            return nil
        }
        let now = env.now()
        let memory = env.store.loadSnapshot()

        if force {
            guard memory.thoughts.count >= 2 else { return nil }
        } else {
            guard memory.thoughts.count >= env.limits.tidyMinimumThoughts else { return nil }
            let last = env.defaults.double(forKey: TidyKey.at)
            guard last > 0 else {
                // Nothing to compare with yet: the week starts now.
                env.defaults.set(now.timeIntervalSince1970, forKey: TidyKey.at)
                return nil
            }
            guard now.timeIntervalSince1970 - last >= env.limits.tidyEvery else { return nil }
            if let pausedUntil, now < pausedUntil { return nil }
            guard requestsToday() < env.limits.dailyRequests else { return nil }
        }

        isRunning = true
        stopRequested = false
        defer { isRunning = false }

        summary.isWorking = true
        summary.workDone = 0
        summary.workTotal = 1
        await publish()

        let request = LLMRequest(
            model: env.model(),
            system: Prompts.tidySystem,
            messages: [
                LLMMessage(role: .user, text: Prompts.tidyMessage(
                    profile: memory.profile,
                    thoughts: Array(memory.thoughts.values),
                    recentDigests: env.store.loadAllDigests(),
                    today: now
                )),
            ],
            maxTokens: AILimits.tidyMaxTokens,
            retryIfDeclined: true,
            jsonSchema: TidySchema.data
        )

        let result: TidyResult
        do {
            countRequest()
            let reply = try await env.provider().complete(request)
            result = try TidyParser.parse(reply.text)
        } catch let error as LLMError where error != .refused && error != .truncated {
            // No network, busy, a bad key: say so quietly and try again another time.
            if error != .aiOff && error != .missingKey {
                summary.problem = error.userMessage(for: env.service())
                pausedUntil = now.addingTimeInterval(env.limits.retryGap)
            }
            summary.isWorking = false
            await publish()
            return nil
        } catch {
            // The answer could not be used. Leave memory as it is until the next tidy is due.
            recordTidy("The last tidy couldn't be used, so nothing was changed.", at: now)
            summary.isWorking = false
            await publish()
            return nil
        }

        // Memory may have changed while waiting (a fix made on the map): start from what is on disk now.
        let current = env.store.loadSnapshot()
        let pins = env.store.loadPins()
        var updated = current
        var texts: [UUID: DigestedEntry?] = [:]
        let files = Dictionary((env.journal.entryFiles() ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let outcome = MemoryTidier.apply(
            result,
            to: &updated,
            pins: pins,
            entry: { id in
                if let known = texts[id] {
                    return known
                }
                var found: DigestedEntry? = nil
                if let file = files[id], let text = self.env.journal.text(of: file) {
                    found = DigestedEntry(id: id, date: MemoryText.day(file.startedAt), text: text)
                }
                texts[id] = found
                return found
            },
            today: MemoryText.day(now),
            rules: MemoryTidier.Rules(oneOffAfterDays: env.limits.oneOffAfterDays)
        )

        do {
            try env.store.write(updated, replacing: current)
        } catch {
            summary.problem = "Couldn't write to the memory folder."
            summary.isWorking = false
            await publish()
            return nil
        }

        recordTidy("Tidied on \(Prompts.longDay(now)): \(outcome.line).", at: now)
        summary.thoughts = updated.thoughts.count
        summary.lastUpdated = now
        summary.problem = nil
        summary.isWorking = false
        await publish()
        return outcome
    }

    private func recordTidy(_ line: String, at date: Date) {
        env.defaults.set(date.timeIntervalSince1970, forKey: TidyKey.at)
        env.defaults.set(line, forKey: TidyKey.line)
        summary.lastTidy = line
    }

    // MARK: - One pass over the journal

    /// Looks for settled entries that are new or changed and digests them, oldest first.
    /// With `everything`, every entry is digested regardless of when it was written (a rebuild).
    @discardableResult
    func runPass(includeFresh: Bool = false, everything: Bool = false) async -> PassOutcome {
        guard env.isEnabled() else {
            return .off
        }
        guard !isRunning else {
            return .busy
        }
        if let pausedUntil, env.now() < pausedUntil, !everything, !includeFresh {
            return .paused
        }
        guard let files = env.journal.entryFiles() else {
            summary.problem = "Couldn't read the journal folder."
            await publish()
            return .unreadable
        }

        isRunning = true
        stopRequested = false
        defer { isRunning = false }

        var memory = env.store.loadSnapshot()
        var digests = Dictionary(env.store.loadAllDigests().map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
        let since = everything ? nil : env.enabledSince()
        let newest = files.last

        // 1. Entries that were deleted take their lines out of memory with them.
        let present = Set(files.map(\.id))
        for (entryID, digest) in digests where !present.contains(entryID) {
            forget(entryID: entryID, wasDigested: !digest.failed, memory: &memory)
            digests[entryID] = nil
        }

        // 2. Find the entries that need digesting.
        struct Work {
            let file: JournalEntryFile
            let text: String
            let hash: String
        }
        var work: [Work] = []
        var waiting = 0

        for file in files {
            let known = digests[file.id]
            if let cached = fingerprints[file.id], cached.modifiedAt == file.modifiedAt, known?.textHash == cached.hash {
                continue
            }
            guard let text = env.journal.text(of: file) else { continue }

            guard env.journal.isDigestible(text, file: file) else {
                // Emptied, or turned into a video entry: nothing of it stays in memory.
                if let known {
                    forget(entryID: file.id, wasDigested: !known.failed, memory: &memory)
                    digests[file.id] = nil
                }
                continue
            }

            let hash = Self.fingerprint(text)
            fingerprints[file.id] = (file.modifiedAt, hash)
            if known?.textHash == hash {
                continue
            }
            // Entries last edited before memory was switched on wait for a rebuild.
            if let since, known == nil, file.modifiedAt < since {
                continue
            }
            // So do entries copied in from freewrite, until they are edited here.
            if !everything, known == nil, let broughtIn = env.broughtInAt(file.id), file.modifiedAt < broughtIn {
                continue
            }

            waiting += 1
            if isSettled(file, newest: newest, includeFresh: includeFresh || everything) {
                work.append(Work(file: file, text: text, hash: hash))
            }
        }

        summary.problem = nil
        summary.waitingEntries = waiting
        summary.thoughts = memory.thoughts.count
        summary.digestedEntries = digests.values.filter { !$0.failed }.count
        summary.isWorking = !work.isEmpty
        summary.workDone = 0
        summary.workTotal = work.count
        await publish()

        // 3. Digest them, oldest first.
        var digested = 0
        for item in work {
            if stopRequested || !env.isEnabled() {
                break
            }
            if !everything, requestsToday() >= env.limits.dailyRequests {
                summary.problem = "Today's limit of \(env.limits.dailyRequests) memory requests has been reached. It carries on tomorrow."
                break
            }

            let entry = DigestedEntry(id: item.file.id, date: MemoryText.day(item.file.startedAt), text: item.text)
            let model = env.model()
            let request = LLMRequest(
                model: model,
                system: Prompts.digestSystem,
                messages: [
                    LLMMessage(role: .user, text: Prompts.digestMessage(
                        profile: memory.profile,
                        thoughts: Array(memory.thoughts.values),
                        entryDate: item.file.startedAt,
                        entryText: item.text
                    )),
                ],
                maxTokens: AILimits.digestMaxTokens,
                retryIfDeclined: true,
                jsonSchema: DigestSchema.data
            )

            var record = EntryDigest(
                entryID: entry.id,
                entryDate: entry.date,
                textHash: item.hash,
                digestedAt: env.now(),
                model: model,
                summary: "",
                thoughts: [],
                openLoops: [],
                rejected: [],
                inputTokens: nil,
                outputTokens: nil,
                failed: false,
                failureReason: nil
            )

            // Ask, then decide what the answer is worth.
            var result: DigestResult? = nil
            var unusableBecause: String? = nil
            do {
                countRequest()
                let reply = try await env.provider().complete(request)
                record.inputTokens = reply.inputTokens
                record.outputTokens = reply.outputTokens
                result = try DigestParser.parse(reply.text)
            } catch let error as DigestParseError {
                // The answer was not usable. Leave this entry until its text changes or memory is rebuilt.
                unusableBecause = error.reason
            } catch LLMError.refused {
                unusableBecause = LLMError.refused.userMessage(for: env.service())
            } catch LLMError.truncated {
                unusableBecause = LLMError.truncated.userMessage(for: env.service())
            } catch let error as LLMError {
                // Anything else (no network, busy, a bad key) stops this pass. It is tried again later.
                if error != .aiOff && error != .missingKey {
                    summary.problem = error.userMessage(for: env.service())
                    pausedUntil = env.now().addingTimeInterval(env.limits.retryGap)
                }
                break
            } catch {
                break
            }

            // Memory may have changed while waiting (a fix made on the map), so start
            // from what is on disk now, with the fixes as they stand now.
            let current = env.store.loadSnapshot()
            let pins = env.store.loadPins()
            var updated = current

            if let result {
                let outcome = MemoryApplier.apply(result, for: entry, to: &updated, pins: pins)
                record.summary = MemoryText.singleLine(result.summary)
                record.thoughts = outcome.touched
                record.openLoops = result.openLoops.map(MemoryText.singleLine).filter { !$0.isEmpty }
                record.rejected = outcome.rejected
            } else {
                MemoryApplier.remove(entryID: entry.id, from: &updated)
                record.failed = true
                record.failureReason = unusableBecause
            }

            do {
                try env.store.write(updated, replacing: current)
                try env.store.saveDigest(record)
            } catch {
                summary.problem = "Couldn't write to the memory folder."
                pausedUntil = env.now().addingTimeInterval(env.limits.retryGap)
                break
            }

            memory = updated
            digests[entry.id] = record
            digested += 1

            summary.workDone = digested
            summary.waitingEntries = max(0, summary.waitingEntries - 1)
            summary.thoughts = memory.thoughts.count
            summary.digestedEntries = digests.values.filter { !$0.failed }.count
            summary.lastUpdated = env.now()
            await publish()
        }

        summary.isWorking = false
        await publish()
        return .finished(digested: digested)
    }

    /// Takes one entry's lines out of memory and removes its digest.
    private func forget(entryID: UUID, wasDigested: Bool, memory: inout MemorySnapshot) {
        if wasDigested {
            var updated = memory
            MemoryApplier.remove(entryID: entryID, from: &updated)
            if (try? env.store.write(updated, replacing: memory)) != nil {
                memory = updated
            }
        }
        env.store.deleteDigest(entryID: entryID)
        fingerprints[entryID] = nil
    }

    private func isSettled(_ file: JournalEntryFile, newest: JournalEntryFile?, includeFresh: Bool) -> Bool {
        let now = env.now()
        let quietFor = now.timeIntervalSince(file.modifiedAt)

        // Never while it is being typed.
        guard quietFor >= env.limits.typingGuard else { return false }

        if includeFresh { return true }
        if quietFor >= env.limits.settleAfter { return true }
        if let newest, newest.id != file.id { return true }
        if MemoryText.day(file.startedAt) < MemoryText.day(now) { return true }
        return false
    }

    // MARK: - Small pieces

    /// A fingerprint of the entry text. The same text always gives the same fingerprint.
    static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private enum CountKey {
        static let day = "memory.requests.day"
        static let count = "memory.requests.count"
    }

    private func requestsToday() -> Int {
        guard env.defaults.string(forKey: CountKey.day) == MemoryText.day(env.now()) else { return 0 }
        return env.defaults.integer(forKey: CountKey.count)
    }

    private func countRequest() {
        let count = requestsToday() + 1
        env.defaults.set(MemoryText.day(env.now()), forKey: CountKey.day)
        env.defaults.set(count, forKey: CountKey.count)
    }

    private func publish() async {
        let current = summary
        let status = self.status
        await MainActor.run {
            status.summary = current
        }
    }
}
