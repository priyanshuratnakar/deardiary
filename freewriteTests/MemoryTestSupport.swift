//
//  MemoryTestSupport.swift
//  freewriteTests
//
//  Helpers for the memory tests: a throwaway journal folder, a clock the test
//  controls, and a made-up week of entries with scripted "AI" digests.
//  Nothing here is real journal content and nothing uses the network.
//

import Foundation
@testable import freewrite

/// A journal folder, memory store and engine that exist only for one test.
final class MemorySandbox: @unchecked Sendable {
    let root: URL
    let store: MemoryStore
    let journal: JournalReader

    /// The time the engine believes it is. Tests move it forward.
    var clock: Date
    var enabled = true
    var enabledSince: Date? = nil
    var model = "model-for-memory"

    private let suiteName = "deardiary.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    static let welcomeText = "Hi. Welcome to the made-up guide.\n\nThis is not the user's writing."

    init(now: Date = MemoryWeek.day(9, hour: 21)) {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Freewrite", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = MemoryStore(root: root)
        journal = JournalReader(root: root, welcomeText: Self.welcomeText)
        defaults = UserDefaults(suiteName: suiteName)!
        clock = now
    }

    func engine(_ provider: FakeProvider, limits: MemoryLimits = MemoryLimits()) -> MemoryEngine {
        MemoryEngine(environment: MemoryEnvironment(
            isEnabled: { [unowned self] in self.enabled },
            enabledSince: { [unowned self] in self.enabledSince },
            model: { [unowned self] in self.model },
            store: store,
            journal: journal,
            provider: { provider },
            now: { [unowned self] in self.clock },
            defaults: defaults,
            limits: limits
        ))
    }

    // MARK: - Writing made-up entries

    static func filename(id: UUID, startedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "[\(id.uuidString)]-[\(formatter.string(from: startedAt))].md"
    }

    /// Writes an entry file, last edited `quietFor` seconds before the sandbox clock.
    @discardableResult
    func writeEntry(_ entry: MemoryWeek.Entry, text: String? = nil, quietFor: TimeInterval = 3600) -> URL {
        let url = root.appendingPathComponent(Self.filename(id: entry.id, startedAt: entry.startedAt))
        try? (text ?? entry.text).write(to: url, atomically: true, encoding: .utf8)
        touch(url, quietFor: quietFor)
        return url
    }

    func touch(_ url: URL, quietFor: TimeInterval) {
        try? FileManager.default.setAttributes(
            [.modificationDate: clock.addingTimeInterval(-quietFor)],
            ofItemAtPath: url.path
        )
    }

    func deleteEntry(_ entry: MemoryWeek.Entry) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(Self.filename(id: entry.id, startedAt: entry.startedAt)))
    }

    func thoughtFileExists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: store.thoughtURL(id).path)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }
}

/// Builds the JSON a digest reply is made of, so tests read like the reply they describe.
enum DigestJSON {
    static func update(_ id: String, quote: String, newSummary: String? = nil, newAlias: String? = nil) -> [String: Any] {
        ["thought_id": id, "quote": quote, "new_summary": newSummary ?? NSNull(), "new_alias": newAlias ?? NSNull()]
    }

    static func new(_ label: String, kind: String, summary: String, aliases: [String] = [], quote: String) -> [String: Any] {
        ["label": label, "kind": kind, "summary": summary, "aliases": aliases, "quote": quote]
    }

    static func link(_ from: String, _ to: String, reason: String, quote: String) -> [String: Any] {
        ["from": from, "to": to, "reason": reason, "quote": quote]
    }

    static func note(_ thought: String, _ note: String, quote: String) -> [String: Any] {
        ["thought": thought, "note": note, "quote": quote]
    }

    static func reply(
        summary: String = "A made-up summary.",
        updates: [[String: Any]] = [],
        new: [[String: Any]] = [],
        links: [[String: Any]] = [],
        notes: [[String: Any]] = [],
        openLoops: [String] = [],
        profile: String? = nil
    ) -> String {
        let object: [String: Any] = [
            "summary": summary,
            "thought_updates": updates,
            "new_thoughts": new,
            "links": links,
            "timeline_notes": notes,
            "open_loops": openLoops,
            "profile": profile ?? NSNull(),
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

/// A made-up week of journal entries, with the digest a model might return for each.
enum MemoryWeek {
    struct Entry {
        let id: UUID
        let startedAt: Date
        let text: String
    }

    /// A moment on a day of November 2026, in the Mac's own time zone.
    static func day(_ day: Int, hour: Int = 8, minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return Calendar.current.date(from: parts)!
    }

    static let monday = Entry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        startedAt: day(2, hour: 23),
        text: """
        Couldn’t sleep again. I keep replaying the call with Meera about the launch.

        I said yes to everything she asked and then felt sick about it for the rest of the day. I don't even know what I was afraid of.
        """
    )

    static let wednesday = Entry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        startedAt: day(4, hour: 7),
        text: """
        Went for a run before work for the first time in weeks. Legs felt heavy but my head was quiet afterwards.

        Told Arjun I might skip the Friday review and he just laughed. The launch date moved again.
        """
    )

    static let friday = Entry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        startedAt: day(6, hour: 22),
        text: """
        Meera asked if I could also take the pricing page. I said I needed to think about it. First time I haven't just said yes.

        Still felt my stomach drop, but I slept fine.
        """
    )

    static let sunday = Entry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        startedAt: day(8, hour: 9),
        text: """
        Slept badly. Too much coffee, and I kept drafting the reply to Meera in my head.

        I think I already know I don't want the pricing page. Need to tell her by Tuesday.
        """
    )

    static let entries = [monday, wednesday, friday, sunday]

    /// What a model might send back for Monday. One item quotes a line that is not in the entry.
    static let mondayReply = DigestJSON.reply(
        summary: "A sleepless night after a call with Meera about the launch. They agreed to everything she asked and felt sick about it afterwards.",
        new: [
            DigestJSON.new("Saying yes under pressure", kind: "theme", summary: "Agreeing in the moment and feeling sick about it afterwards.", aliases: ["can't say no"], quote: "I said yes to everything she asked and then felt sick about it"),
            DigestJSON.new("Meera", kind: "person", summary: "A colleague leading the launch, whose requests are hard to refuse.", quote: "I keep replaying the call with Meera about the launch."),
            DigestJSON.new("Trouble sleeping", kind: "feeling", summary: "Nights of poor sleep, often after something left unresolved.", quote: "Couldn't sleep again."),
            DigestJSON.new("The launch", kind: "event", summary: "A launch at work that keeps pulling at their attention.", quote: "the call with Meera about the launch"),
            DigestJSON.new("Fear of failing", kind: "feeling", summary: "A worry about not being good enough.", quote: "I am terrified of failing at this."),
        ],
        links: [
            DigestJSON.link("Saying yes under pressure", "Meera", reason: "shows up around", quote: "I said yes to everything she asked"),
            DigestJSON.link("Trouble sleeping", "Saying yes under pressure", reason: "follows", quote: "Couldn't sleep again. I keep replaying the call"),
        ],
        profile: "They are in the middle of a launch at work and find it hard to refuse Meera, who leads it. Agreeing to things they do not want leaves them uneasy and costs them sleep."
    )

    static let wednesdayReply = DigestJSON.reply(
        summary: "A first run in weeks left their head quiet. They joked with Arjun about skipping the Friday review, and the launch date moved again.",
        updates: [
            DigestJSON.update("the-launch", quote: "The launch date moved again."),
        ],
        new: [
            DigestJSON.new("Running", kind: "idea", summary: "Running before work as a way to quiet the mind.", quote: "Went for a run before work for the first time in weeks."),
            DigestJSON.new("Arjun", kind: "person", summary: "A colleague they can be light with.", quote: "Told Arjun I might skip the Friday review and he just laughed."),
        ],
        notes: [
            DigestJSON.note("the-launch", "The date moved again.", quote: "The launch date moved again."),
        ],
        openLoops: ["Decide whether to skip the Friday review"]
    )

    /// Friday's reply tries to create "Saying yes", which memory already holds under another name.
    static let fridayReply = DigestJSON.reply(
        summary: "Meera asked for more and, for the first time, they did not agree on the spot. Their stomach dropped, but they slept fine.",
        updates: [
            DigestJSON.update("meera", quote: "Meera asked if I could also take the pricing page."),
            DigestJSON.update("trouble-sleeping", quote: "but I slept fine"),
        ],
        new: [
            DigestJSON.new("Saying yes", kind: "theme", summary: "Agreeing too quickly.", aliases: ["Saying yes under pressure"], quote: "First time I haven't just said yes."),
            DigestJSON.new("The pricing page", kind: "decision", summary: "Whether to take on the pricing page Meera asked for.", quote: "I said I needed to think about it."),
        ],
        links: [
            DigestJSON.link("The pricing page", "meera", reason: "asked for by", quote: "Meera asked if I could also take the pricing page."),
        ],
        notes: [
            DigestJSON.note("saying-yes-under-pressure", "Held back from agreeing for the first time.", quote: "First time I haven't just said yes."),
            DigestJSON.note("trouble-sleeping", "Slept fine after not agreeing straight away.", quote: "Still felt my stomach drop, but I slept fine."),
        ]
    )

    static let sundayReply = DigestJSON.reply(
        summary: "A bad night, partly coffee and partly drafting a reply to Meera. They think they do not want the pricing page and need to say so by Tuesday.",
        updates: [
            DigestJSON.update("trouble-sleeping", quote: "Slept badly."),
            DigestJSON.update("meera", quote: "I kept drafting the reply to Meera in my head"),
            DigestJSON.update("the-pricing-page", quote: "I think I already know I don't want the pricing page.", newSummary: "Whether to take on the pricing page Meera asked for. They are leaning towards no."),
        ],
        notes: [
            DigestJSON.note("the-pricing-page", "Leaning towards saying no.", quote: "I think I already know I don't want the pricing page."),
        ],
        openLoops: ["Tell Meera about the pricing page by Tuesday"],
        profile: "They are in the middle of a launch at work led by Meera. A pattern of agreeing under pressure has started to shift: this week they held back for the first time, and they are leaning towards turning down the pricing page. Sleep suffers when something with Meera is unresolved. Running and time with Arjun are lighter spots."
    )

    static let replies = [mondayReply, wednesdayReply, fridayReply, sundayReply]

    static func digested(_ entry: Entry) -> DigestedEntry {
        DigestedEntry(id: entry.id, date: MemoryText.day(entry.startedAt), text: entry.text)
    }

    /// Memory as it stands after the whole week has been digested, with the digest kept for each entry.
    static func built() throws -> (memory: MemorySnapshot, digests: [EntryDigest]) {
        var memory = MemorySnapshot()
        var digests: [EntryDigest] = []
        for (entry, reply) in zip(entries, replies) {
            let result = try DigestParser.parse(reply)
            let outcome = MemoryApplier.apply(result, for: digested(entry), to: &memory, pins: Pins())
            digests.append(EntryDigest(
                entryID: entry.id,
                entryDate: MemoryText.day(entry.startedAt),
                textHash: MemoryEngine.fingerprint(entry.text),
                digestedAt: day(9, hour: 21),
                model: "model-for-memory",
                summary: result.summary,
                thoughts: outcome.touched,
                openLoops: result.openLoops,
                rejected: outcome.rejected,
                inputTokens: nil,
                outputTokens: nil,
                failed: false,
                failureReason: nil
            ))
        }
        return (memory, digests)
    }
}
