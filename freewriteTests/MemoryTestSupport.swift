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
    /// When an entry was copied in from freewrite, for the tests about moving in.
    var broughtInAt: (UUID) -> Date? = { _ in nil }

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

    /// Limits for tests: as in the app, except that a rebuild does not end with a tidy
    /// (tests that are about the tidy switch it back on).
    static var quietLimits: MemoryLimits {
        var limits = MemoryLimits()
        limits.tidyAfterRebuild = false
        return limits
    }

    func engine(_ provider: FakeProvider, limits: MemoryLimits = MemorySandbox.quietLimits) -> MemoryEngine {
        MemoryEngine(environment: MemoryEnvironment(
            isEnabled: { [unowned self] in self.enabled },
            enabledSince: { [unowned self] in self.enabledSince },
            model: { [unowned self] in self.model },
            store: store,
            journal: journal,
            provider: { provider },
            broughtInAt: { [unowned self] in self.broughtInAt($0) },
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

/// Builds the JSON a reading of one entry is made of, so tests read like the reply they describe.
enum DigestJSON {
    /// A person or a topic.
    static func named(_ name: String, _ quote: String) -> [String: Any] {
        ["name": name, "quote": quote]
    }

    static func felt(_ word: String, _ tone: String, _ quote: String) -> [String: Any] {
        ["word": word, "tone": tone, "quote": quote]
    }

    /// Something that happened, helped, matters or is still open.
    static func noted(_ what: String, _ quote: String) -> [String: Any] {
        ["what": what, "quote": quote]
    }

    static func reply(
        people: [[String: Any]] = [],
        topics: [[String: Any]] = [],
        feelings: [[String: Any]] = [],
        happened: [[String: Any]] = [],
        selfTalk: [String] = [],
        helped: [[String: Any]] = [],
        matters: [[String: Any]] = [],
        openLoops: [[String: Any]] = []
    ) -> String {
        let object: [String: Any] = [
            "people": people,
            "topics": topics,
            "feelings": feelings,
            "happened": happened,
            "self_talk": selfTalk.map { ["quote": $0] },
            "helped": helped,
            "matters": matters,
            "open_loops": openLoops,
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

    /// What a model might send back for Monday, in the shape memory has had since M14.
    /// One feeling quotes a line that is not in the entry.
    static let mondayReply = DigestJSON.reply(
        people: [DigestJSON.named("Meera", "the call with Meera")],
        topics: [DigestJSON.named("the launch", "the call with Meera about the launch")],
        feelings: [
            DigestJSON.felt("Couldn't sleep", "unpleasant", "Couldn't sleep again."),
            DigestJSON.felt("felt sick", "unpleasant", "felt sick about it for the rest of the day"),
            DigestJSON.felt("terrified", "unpleasant", "I am terrified of failing at this."),
        ],
        happened: [DigestJSON.noted("said yes to everything", "I said yes to everything she asked")],
        selfTalk: ["I don't even know what I was afraid of."]
    )

    static let wednesdayReply = DigestJSON.reply(
        people: [DigestJSON.named("Arjun", "Told Arjun I might skip the Friday review")],
        topics: [
            DigestJSON.named("the launch", "The launch date moved again."),
            DigestJSON.named("the Friday review", "Told Arjun I might skip the Friday review"),
        ],
        feelings: [
            DigestJSON.felt("heavy", "unpleasant", "Legs felt heavy"),
            DigestJSON.felt("quiet", "pleasant", "my head was quiet afterwards"),
        ],
        happened: [DigestJSON.noted("went for a run before work", "Went for a run before work for the first time in weeks.")],
        helped: [DigestJSON.noted("a run before work", "Went for a run before work for the first time in weeks. Legs felt heavy but my head was quiet afterwards.")]
    )

    static let fridayReply = DigestJSON.reply(
        people: [DigestJSON.named("Meera", "Meera asked if I could also take the pricing page.")],
        topics: [DigestJSON.named("the pricing page", "Meera asked if I could also take the pricing page.")],
        feelings: [
            DigestJSON.felt("stomach drop", "unpleasant", "Still felt my stomach drop"),
            DigestJSON.felt("slept fine", "pleasant", "but I slept fine."),
        ],
        happened: [DigestJSON.noted("Meera asked about the pricing page", "Meera asked if I could also take the pricing page.")],
        selfTalk: ["First time I haven't just said yes."],
        openLoops: [DigestJSON.noted("think about it", "I said I needed to think about it.")]
    )

    /// Sunday's reply calls the pricing page "pricing page", which memory already holds as "the pricing page".
    static let sundayReply = DigestJSON.reply(
        people: [DigestJSON.named("Meera", "I kept drafting the reply to Meera in my head.")],
        topics: [DigestJSON.named("pricing page", "I think I already know I don't want the pricing page.")],
        feelings: [DigestJSON.felt("Slept badly", "unpleasant", "Slept badly.")],
        selfTalk: ["I think I already know I don't want the pricing page."],
        matters: [DigestJSON.noted("don't want the pricing page", "I think I already know I don't want the pricing page.")],
        openLoops: [DigestJSON.noted("tell her by Tuesday", "Need to tell her by Tuesday.")]
    )

    static let replies = [mondayReply, wednesdayReply, fridayReply, sundayReply]

    static func digested(_ entry: Entry) -> DigestedEntry {
        DigestedEntry(id: entry.id, date: MemoryText.day(entry.startedAt), text: entry.text)
    }

    /// Memory as it stands after the whole week has been read in the shape of a journal,
    /// with the digest kept for each entry (the day's lines included).
    static func read() throws -> (memory: MemorySnapshot, digests: [EntryDigest]) {
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
                summary: "",
                thoughts: outcome.touched,
                openLoops: outcome.lines.filter { $0.kind == .stillOpen }.map(\.quote),
                rejected: outcome.rejected,
                inputTokens: nil,
                outputTokens: nil,
                failed: false,
                failureReason: nil,
                lines: outcome.lines
            ))
            FeelingDots.reconcile(&memory, with: digests, pins: Pins())
        }
        memory.profile = MemoryCounts.profile(memory: memory, today: MemoryText.day(day(9, hour: 21)))
        return (memory, digests)
    }

    /// The day's lines from `read()`, in the form the map takes them.
    static func dayLines() throws -> [UUID: (date: String, lines: [DayLine])] {
        var result: [UUID: (date: String, lines: [DayLine])] = [:]
        for digest in try read().digests {
            result[digest.entryID] = (digest.entryDate, digest.lines ?? [])
        }
        return result
    }

    // MARK: - The same week, as memory was built before M14

    /// Memory for the same week as the app built it before M14, when the AI named and
    /// described thoughts itself. It is kept exactly as that version produced it, because
    /// a memory folder built then is still on people's Macs until they rebuild it, and it
    /// has to keep working: the map, the fixes and talk are all tested against it.
    static func built() throws -> (memory: MemorySnapshot, digests: [EntryDigest]) {
        var memory = MemorySnapshot()
        for thought in olderThoughts {
            memory.thoughts[thought.id] = thought
        }
        memory.profile = "They are in the middle of a launch at work led by Meera. A pattern of agreeing under pressure has started to shift: this week they held back for the first time, and they are leaning towards turning down the pricing page. Sleep suffers when something with Meera is unresolved. Running and time with Arjun are lighter spots."

        func digest(_ entry: Entry, _ summary: String, _ thoughts: [String], openLoops: [String] = [], rejected: [EntryDigest.Rejection] = []) -> EntryDigest {
            EntryDigest(
                entryID: entry.id,
                entryDate: MemoryText.day(entry.startedAt),
                textHash: MemoryEngine.fingerprint(entry.text),
                digestedAt: day(9, hour: 21),
                model: "model-for-memory",
                summary: summary,
                thoughts: thoughts,
                openLoops: openLoops,
                rejected: rejected,
                inputTokens: nil,
                outputTokens: nil,
                failed: false,
                failureReason: nil
            )
        }
        let digests = [
            digest(monday, "A sleepless night after a call with Meera about the launch. They agreed to everything she asked and felt sick about it afterwards.", ["meera", "saying-yes-under-pressure", "the-launch", "trouble-sleeping"], rejected: [EntryDigest.Rejection(item: "new_thought", reason: "Its quote is not in the entry.")]),
            digest(wednesday, "A first run in weeks left their head quiet. They joked with Arjun about skipping the Friday review, and the launch date moved again.", ["arjun", "running", "the-launch"], openLoops: ["Decide whether to skip the Friday review"]),
            digest(friday, "Meera asked for more and, for the first time, they did not agree on the spot. Their stomach dropped, but they slept fine.", ["meera", "saying-yes-under-pressure", "the-pricing-page", "trouble-sleeping"]),
            digest(sunday, "A bad night, partly coffee and partly drafting a reply to Meera. They think they do not want the pricing page and need to say so by Tuesday.", ["meera", "the-pricing-page", "trouble-sleeping"], openLoops: ["Tell Meera about the pricing page by Tuesday"]),
        ]
        return (memory, digests)
    }

    private static var olderThoughts: [Thought] {
        [
            Thought(
                id: "arjun", label: "Arjun", kind: .person,
                aliases: [],
                summary: "A colleague they can be light with.",
                timeline: [],
                evidence: [
                    Evidence(entryID: wednesday.id, date: "2026-11-04", quote: "Told Arjun I might skip the Friday review and he just laughed."),
                ],
                links: []
            ),
            Thought(
                id: "meera", label: "Meera", kind: .person,
                aliases: [],
                summary: "A colleague leading the launch, whose requests are hard to refuse.",
                timeline: [],
                evidence: [
                    Evidence(entryID: monday.id, date: "2026-11-02", quote: "I keep replaying the call with Meera about the launch."),
                    Evidence(entryID: friday.id, date: "2026-11-06", quote: "Meera asked if I could also take the pricing page."),
                    Evidence(entryID: sunday.id, date: "2026-11-08", quote: "I kept drafting the reply to Meera in my head"),
                ],
                links: []
            ),
            Thought(
                id: "running", label: "Running", kind: .idea,
                aliases: [],
                summary: "Running before work as a way to quiet the mind.",
                timeline: [],
                evidence: [
                    Evidence(entryID: wednesday.id, date: "2026-11-04", quote: "Went for a run before work for the first time in weeks."),
                ],
                links: []
            ),
            Thought(
                id: "saying-yes-under-pressure", label: "Saying yes under pressure", kind: .theme,
                aliases: ["can't say no", "Saying yes"],
                summary: "Agreeing in the moment and feeling sick about it afterwards.",
                timeline: [TimelineNote(entryID: friday.id, date: "2026-11-06", note: "Held back from agreeing for the first time.", quote: "First time I haven't just said yes.")],
                evidence: [
                    Evidence(entryID: monday.id, date: "2026-11-02", quote: "I said yes to everything she asked and then felt sick about it"),
                    Evidence(entryID: friday.id, date: "2026-11-06", quote: "First time I haven't just said yes."),
                ],
                links: [ThoughtLink(target: "meera", reason: "shows up around", entryID: monday.id, date: "2026-11-02", quote: "I said yes to everything she asked")]
            ),
            Thought(
                id: "the-launch", label: "The launch", kind: .event,
                aliases: [],
                summary: "A launch at work that keeps pulling at their attention.",
                timeline: [TimelineNote(entryID: wednesday.id, date: "2026-11-04", note: "The date moved again.", quote: "The launch date moved again.")],
                evidence: [
                    Evidence(entryID: monday.id, date: "2026-11-02", quote: "the call with Meera about the launch"),
                    Evidence(entryID: wednesday.id, date: "2026-11-04", quote: "The launch date moved again."),
                ],
                links: []
            ),
            Thought(
                id: "the-pricing-page", label: "The pricing page", kind: .decision,
                aliases: [],
                summary: "Whether to take on the pricing page Meera asked for. They are leaning towards no.",
                timeline: [TimelineNote(entryID: sunday.id, date: "2026-11-08", note: "Leaning towards saying no.", quote: "I think I already know I don't want the pricing page.")],
                evidence: [
                    Evidence(entryID: friday.id, date: "2026-11-06", quote: "I said I needed to think about it."),
                    Evidence(entryID: sunday.id, date: "2026-11-08", quote: "I think I already know I don't want the pricing page."),
                ],
                links: [ThoughtLink(target: "meera", reason: "asked for by", entryID: friday.id, date: "2026-11-06", quote: "Meera asked if I could also take the pricing page.")]
            ),
            Thought(
                id: "trouble-sleeping", label: "Trouble sleeping", kind: .feeling,
                aliases: [],
                summary: "Nights of poor sleep, often after something left unresolved.",
                timeline: [TimelineNote(entryID: friday.id, date: "2026-11-06", note: "Slept fine after not agreeing straight away.", quote: "Still felt my stomach drop, but I slept fine.")],
                evidence: [
                    Evidence(entryID: monday.id, date: "2026-11-02", quote: "Couldn’t sleep again."),
                    Evidence(entryID: friday.id, date: "2026-11-06", quote: "but I slept fine"),
                    Evidence(entryID: sunday.id, date: "2026-11-08", quote: "Slept badly."),
                ],
                links: [ThoughtLink(target: "saying-yes-under-pressure", reason: "follows", entryID: monday.id, date: "2026-11-02", quote: "Couldn’t sleep again. I keep replaying the call")]
            ),
        ]
    }
}
