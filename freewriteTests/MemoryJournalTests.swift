//
//  MemoryJournalTests.swift
//  freewriteTests
//
//  Memory in the shape of a journal (M14), as the user meets it: the kinds in
//  words, what the app says by counting, the names handed to the AI, and what
//  the map's panel shows for a person, a feeling, something that helped,
//  something still open, and a day. Uses the made-up week.
//

import XCTest
import SwiftUI
import Testing
@testable import freewrite

@Suite struct ThoughtKindTests {

    @Test func theKindsAJournalKeepsComeFirstAndReadAsWords() {
        #expect(ThoughtKind.journal == [.person, .topic, .feeling, .helped, .open])
        #expect(Array(ThoughtKind.allCases.prefix(5)) == ThoughtKind.journal)
        #expect(ThoughtKind.journal.map(\.name) == ["person", "topic", "feeling", "what helped", "still open"])
        // A kind from before M14 is still read, and still says what it was.
        #expect(ThoughtKind(loose: " Theme ") == .theme)
        #expect(ThoughtKind.decision.name == "decision")
        #expect(ThoughtKind(loose: "diagnosis") == nil)
    }

    @Test func anOlderNoteWithNoKindIsATopic() throws {
        let thought = try #require(ThoughtNote.parse("---\nlabel: Rent\n---\n\n# Rent\n", id: "rent"))

        #expect(thought.kind == .topic)
    }

    @Test func theNewKindsWriteAndReadBackAsNotes() throws {
        for kind in ThoughtKind.journal {
            let thought = Thought(
                id: "made-up", label: "Made up", kind: kind,
                evidence: [Evidence(entryID: MemoryWeek.monday.id, date: "2026-11-02", quote: "A made-up line.")]
            )
            #expect(ThoughtNote.parse(ThoughtNote.render(thought), id: "made-up") == thought)
        }
    }
}

@Suite struct MemoryCountsTests {

    private func counted(_ id: String) throws -> [String] {
        let read = try MemoryWeek.read()
        let thought = try #require(read.memory.thoughts[id])
        let lines = Dictionary(uniqueKeysWithValues: read.digests.map { ($0.entryID, $0.lines ?? []) })
        return MemoryCounts.lines(for: thought, dayLines: lines)
    }

    @Test func aPersonSaysHowOftenAndHowManyOfThoseDaysHadAnUnpleasantFeeling() throws {
        #expect(try counted("meera") == [
            "In 3 entries, from Monday 2 November to Sunday 8 November 2026.",
            "On 3 of those 3 days you also named an unpleasant feeling.",
        ])
    }

    @Test func twoDaysAreTooFewToCountFeelingsAndOneDayIsJustADay() throws {
        // The launch is in two entries: a coincidence, not a count.
        #expect(try counted("the-launch") == ["In 2 entries, from Monday 2 November to Wednesday 4 November 2026."])
        #expect(try counted("arjun") == ["In 1 entry, on Wednesday 4 November 2026."])
    }

    @Test func whatHelpedAndWhatIsStillOpenSayJustThat() throws {
        #expect(try counted("a-run-before-work") == ["You wrote that this helped on 1 day."])
        #expect(try counted("need-to-tell-her-by-tuesday") == ["Open since Sunday 8 November 2026."])
    }

    @Test func aFeelingSaysOnHowManyDaysAndWhetherTheyWerePleasant() {
        func feeling(_ tones: [DayLine.Tone]) -> [String] {
            var thought = Thought(id: "felt-tired", label: "tired", kind: .feeling)
            var lines: [UUID: [DayLine]] = [:]
            for (index, tone) in tones.enumerated() {
                let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
                thought.evidence.append(Evidence(entryID: id, date: "2026-11-1\(index)", quote: "Tired, day \(index)."))
                lines[id] = [DayLine(kind: .felt, quote: "Tired, day \(index).", word: "tired", tone: tone)]
            }
            return MemoryCounts.lines(for: thought, dayLines: lines)
        }

        #expect(feeling([.unpleasant, .unpleasant]) == ["Named on 2 days, both unpleasant."])
        #expect(feeling([.unpleasant, .unpleasant, .unpleasant]) == ["Named on 3 days, all unpleasant."])
        #expect(feeling([.unpleasant, .pleasant, .unpleasant]) == ["Named on 3 days: 2 unpleasant, 1 pleasant."])
    }

    @Test func aThoughtFromBeforeM14IsCountedWithoutFeelingsItWasNeverGiven() throws {
        let older = try MemoryWeek.built().memory
        let meera = try #require(older.thoughts["meera"])

        // No day was read in the writer's own words, so nothing is said about feelings.
        #expect(MemoryCounts.lines(for: meera, dayLines: [:]) == ["In 3 entries, from Monday 2 November to Sunday 8 November 2026."])
    }

    @Test func theYearIsSaidOnceUnlessItChanges() {
        #expect(MemoryCounts.span("2026-11-02", "2026-11-08") == "Monday 2 November to Sunday 8 November 2026")
        #expect(MemoryCounts.span("2026-12-28", "2027-01-04") == "Monday 28 December 2026 to Monday 4 January 2027")
    }

    @Test func theCountedLinesNeverClaimACause() throws {
        let read = try MemoryWeek.read()
        let lines = Dictionary(uniqueKeysWithValues: read.digests.map { ($0.entryID, $0.lines ?? []) })
        let everything = read.memory.thoughts.values.flatMap { MemoryCounts.lines(for: $0, dayLines: lines) } + [read.memory.profile]

        for line in everything {
            for word in ["because", "always", "tends", "often", "usually", "causes", "leads to"] {
                #expect(!line.lowercased().contains(word), "\(line)")
            }
        }
    }

    @Test func theProfileIsEmptyUntilThereIsSomethingToCount() {
        #expect(MemoryCounts.profile(memory: MemorySnapshot(), today: "2026-11-09") == "")

        var memory = MemorySnapshot()
        memory.thoughts["ma"] = Thought(id: "ma", label: "Ma", kind: .person, evidence: [Evidence(entryID: MemoryWeek.monday.id, date: "2026-11-02", quote: "Ma called.")])
        // One mention is not "most written about".
        #expect(MemoryCounts.profile(memory: memory, today: "2026-11-09") == "")
    }

    @Test func onlyTheLastMonthCountsAsLately() throws {
        let memory = try MemoryWeek.read().memory

        #expect(MemoryCounts.profile(memory: memory, today: "2026-11-09").hasPrefix("Most written about in the last month: Meera (3 entries)"))
        // Two months on, nothing has been written about lately; what is open is still open.
        #expect(MemoryCounts.profile(memory: memory, today: "2027-01-15") == """
        Still open: 2 things, the oldest since Friday 6 November 2026.
        They wrote that these helped: a run before work.
        """)
    }
}

@Suite struct MemoryIndexTests {

    @Test func theNamesHandedToTheAIAreNamesOnly() throws {
        let read = try MemoryWeek.read()
        let index = MemoryIndex(memory: read.memory, digests: read.digests)

        // The most recently written about first.
        #expect(index.people == ["Meera", "Arjun"])
        // Something that helped is still a thing they may write about again; open things are not names.
        #expect(index.topics == ["the pricing page", "a run before work", "the Friday review", "the launch"])
        // Feelings in their own words, the most recent first, each once.
        #expect(index.feelings == [
            "Slept badly (unpleasant)", "stomach drop (unpleasant)", "slept fine (pleasant)",
            "heavy (unpleasant)", "quiet (pleasant)", "Couldn't sleep (unpleasant)", "felt sick (unpleasant)",
        ])

        let message = Prompts.digestMessage(index: index, entryDate: MemoryWeek.day(10), entryText: "\n\nA new entry.\n")
        #expect(message.hasPrefix("People already in memory: Meera, Arjun\nTopics already in memory: the pricing page, "))
        #expect(message.hasSuffix("Entry written on Tuesday 10 November 2026:\n<entry>\nA new entry.\n</entry>"))
        // No line from any earlier entry goes with the names.
        for digest in read.digests {
            for line in digest.lines ?? [] {
                #expect(!message.contains(line.quote))
            }
        }
    }

    @Test func aMemoryFromBeforeM14OffersItsPeopleButNotTheAIsOwnThemes() throws {
        let older = try MemoryWeek.built()
        let index = MemoryIndex(memory: older.memory, digests: older.digests)

        #expect(index.people == ["Meera", "Arjun"])
        // "Saying yes under pressure" was the AI's name for something. It is not handed back as a topic.
        #expect(index.topics.isEmpty)
        #expect(index.feelings.isEmpty)
    }

    @Test func theInstructionsAskForTheWritersWordsAndNothingAboutThem() {
        let system = Prompts.digestSystem

        #expect(system.contains("using only the writer's own words as proof"))
        #expect(system.contains("copy the words exactly from the entry"))
        #expect(system.contains("Do not add feelings they did not name."))
        #expect(system.contains("Do not add causes they did not state."))
        // Nothing asks for a description, a summary, a pattern or a profile.
        for word in ["summary", "profile", "pattern", "theme", "diagnos"] {
            #expect(!system.lowercased().contains(word), "\(word)")
        }
        // The example in the instructions is itself in the shape that is asked for.
        let example = try? DigestParser.parse(String(system[system.range(of: "{\"people\"")!.lowerBound...]))
        #expect(example?.helped.first?.what == "the walk back")
    }
}

@MainActor
@Suite struct JournalMapTests {

    private let size = CGSize(width: 1100, height: 600)

    private func model(pins: Pins = Pins(), extra: [UUID: (date: String, lines: [DayLine])] = [:]) throws -> MapModel {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        var lines = try MemoryWeek.dayLines()
        for (id, day) in extra {
            lines[id] = day
        }
        model.show(memory: try MemoryWeek.read().memory, dayLines: lines, pins: pins)
        model.fit(in: size)
        return model
    }

    @Test func theMapHoldsTheLastingThingsAndTheDays() throws {
        let model = try model()

        #expect(model.graph.thoughts.count == 8)
        #expect(model.graph.days.count == 4)
        #expect(Set(model.graph.thoughts.compactMap(\.kind)) == [.person, .topic, .helped, .open])
        #expect(model.countLine == "8 thoughts · 4 days")
        // A link is a shared sentence.
        #expect(model.graph.edges.filter { !$0.isDayLink }.allSatisfy { $0.reasons == [MemoryApplier.sameSentence] })
        #expect(model.graph.edges.contains { $0.id == "meera|the-pricing-page" })
    }

    @Test func aPersonShowsTheCountsAndEachDayWithWhatElseWasFeltAndSaid() throws {
        let detail = try #require(try model().thoughtDetail("meera"))

        #expect(detail.kind == .person)
        #expect(detail.summary.isEmpty)
        #expect(detail.shifts.isEmpty)
        #expect(detail.counted == [
            "In 3 entries, from Monday 2 November to Sunday 8 November 2026.",
            "On 3 of those 3 days you also named an unpleasant feeling.",
        ])
        // The most recent day first.
        #expect(detail.days.map(\.date) == ["2026-11-08", "2026-11-06", "2026-11-02"])

        let sunday = try #require(detail.days.first)
        #expect(sunday.quotes == ["I kept drafting the reply to Meera in my head."])
        #expect(sunday.lines == [
            MapTaggedLine(tag: "felt", quote: "Slept badly.", note: "unpleasant"),
            // The same line is both what they told themselves and what they want: it is shown once.
            MapTaggedLine(tag: "told yourself", quote: "I think I already know I don't want the pricing page."),
            MapTaggedLine(tag: "still open", quote: "Need to tell her by Tuesday."),
        ])

        let friday = detail.days[1]
        // What happened is left out here, and so is her own line, which is already shown above.
        #expect(friday.lines.map(\.tag) == ["felt", "felt", "told yourself", "still open"])
        #expect(!friday.lines.contains { $0.quote == "Meera asked if I could also take the pricing page." })
        #expect(detail.connections.map(\.label) == ["the launch", "the pricing page"])
        #expect(detail.connections.allSatisfy { $0.reasons == [MemoryApplier.sameSentence] })
    }

    @Test func aDayShowsItsLinesInASteadyOrderAndWhatItTouched() throws {
        let detail = try #require(try model().dayDetail(MemoryWeek.friday.id))

        #expect(detail.summary == nil)
        #expect(detail.lines == [
            MapTaggedLine(tag: "felt", quote: "Still felt my stomach drop", note: "unpleasant"),
            MapTaggedLine(tag: "felt", quote: "but I slept fine.", note: "pleasant"),
            MapTaggedLine(tag: "told yourself", quote: "First time I haven't just said yes."),
            MapTaggedLine(tag: "happened", quote: "Meera asked if I could also take the pricing page."),
            MapTaggedLine(tag: "still open", quote: "I said I needed to think about it."),
        ])
        #expect(detail.thoughts.map(\.label) == ["I said I needed to think about it", "Meera", "the pricing page"])
    }

    @Test func aLineAboutSomethingTheUserClosedSaysSo() throws {
        var pins = Pins()
        pins.deletions = [Pins.Deletion(id: "need-to-tell-her-by-tuesday", label: "Need to tell her by Tuesday", settled: "done", on: "2026-11-10")]
        var memory = try MemoryWeek.read().memory
        MemoryFixes.enforce(pins, on: &memory)
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        model.show(memory: memory, dayLines: try MemoryWeek.dayLines(), pins: pins)

        #expect(model.thoughtDetail("need-to-tell-her-by-tuesday") == nil)
        let sunday = try #require(model.dayDetail(MemoryWeek.sunday.id))
        #expect(sunday.lines.last == MapTaggedLine(tag: "done", quote: "Need to tell her by Tuesday."))

        pins.deletions[0].settled = "dropped"
        model.show(memory: memory, dayLines: try MemoryWeek.dayLines(), pins: pins)
        #expect(model.dayDetail(MemoryWeek.sunday.id)?.lines.last?.tag == "not doing it")
    }

    @Test func aDayThatTouchedNothingLastingIsStillOnTheMap() throws {
        // An entry with only a feeling and something they told themselves: no person, no topic.
        let lonely = UUID(uuidString: "00000000-0000-0000-0000-000000000017")!
        let model = try model(extra: [lonely: ("2026-11-17", [
            DayLine(kind: .felt, quote: "3am. Awake.", word: "Awake", tone: .mixed),
            DayLine(kind: .toldYourself, quote: "Nobody will remember it. I will."),
        ])])

        #expect(model.graph.days.count == 5)
        let node = try #require(model.graph.nodes.first { $0.entryID == lonely })
        #expect(node.weight == 0)
        #expect(!model.graph.edges.contains { $0.first == node.id || $0.second == node.id })

        let detail = try #require(model.dayDetail(lonely))
        #expect(detail.thoughts.isEmpty)
        #expect(detail.lines.map(\.tag) == ["felt", "told yourself"])
        // A day whose entry left no lines at all is not added.
        let empty = UUID(uuidString: "00000000-0000-0000-0000-000000000018")!
        #expect(try self.model(extra: [empty: ("2026-11-18", [])]).graph.days.count == 4)
    }

    @Test func aLongNameIsCutShortOnTheMapAndWholeInThePanel() throws {
        let model = try model()
        let node = try #require(model.graph.nodes.first { $0.id == "i-said-i-needed-to-think-about-it" })

        #expect(node.label == "I said I needed to think about it")
        #expect(node.mapLabel == "I said I needed to think about it")

        var long = node
        long.label = "I still need to decide whether to tell Papa about the rent going up in January"
        #expect(long.mapLabel == "I still need to decide whether t…")
        #expect(long.mapLabel.count <= 34)
    }

    @Test func aSentenceForANameGivesWayToAShortNameItWouldCover() throws {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        let line = Evidence(entryID: MemoryWeek.friday.id, date: "2026-11-06", quote: "I said I needed to think about it.")
        var memory = MemorySnapshot()
        memory.thoughts["ma"] = Thought(id: "ma", label: "Ma", kind: .person, evidence: [line])
        memory.thoughts["open"] = Thought(id: "open", label: "I said I needed to think about it", kind: .open, evidence: [line])
        // The two dots sit almost on top of each other, so their names would collide.
        model.show(memory: memory, positions: [
            "ma": CGPoint(x: 0, y: 0), "open": CGPoint(x: 14, y: 2), GraphNode.dayID(MemoryWeek.friday.id): CGPoint(x: 200, y: 200),
        ])

        let names = model.placedLabels(in: size, fontName: "Lato-Regular").map(\.label)
        #expect(names == ["Ma"])

        // Selecting the open thing brings its name back, whatever it covers.
        model.selection = .thought("open")
        #expect(model.placedLabels(in: size, fontName: "Lato-Regular").map(\.label).contains("I said I needed to think about it"))

        // Far enough apart, both are named.
        model.selection = nil
        model.show(memory: memory, positions: [
            "ma": CGPoint(x: -300, y: 0), "open": CGPoint(x: 300, y: 0), GraphNode.dayID(MemoryWeek.friday.id): CGPoint(x: 0, y: 200),
        ])
        #expect(Set(model.placedLabels(in: size, fontName: "Lato-Regular").map(\.label)) == ["Ma", "I said I needed to think about it"])
    }

    @Test func theNewKindsShareTheTestedColoursOfTheOldOnesTheyReplace() {
        for dark in [false, true] {
            let style = MapStyle(fontName: "Lato-Regular", isLight: !dark)
            #expect(style.color(for: .topic) == style.color(for: .theme))
            #expect(style.color(for: .helped) == style.color(for: .event))
            #expect(style.color(for: .open) == style.color(for: .question))
            // The five kinds memory keeps now are five different colours.
            #expect(Set(ThoughtKind.journal.map { style.color(for: $0).description }).count == 5)
        }
    }
}

@MainActor
@Suite struct MapSettleFlowTests {

    /// A throwaway memory folder holding the made-up week in the shape of a journal,
    /// and a map over it whose fixes go through the real engine.
    private func map() async throws -> (sandbox: MemorySandbox, model: MapModel) {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        let read = try MemoryWeek.read()
        try sandbox.store.write(read.memory, replacing: MemorySnapshot())
        for digest in read.digests {
            try sandbox.store.saveDigest(digest)
        }
        let engine = sandbox.engine(FakeProvider())
        let model = MapModel(store: sandbox.store, applyFix: { await engine.fix($0) })
        await model.load()
        model.fit(in: CGSize(width: 1100, height: 600))
        return (sandbox, model)
    }

    @Test func markingSomethingDoneTakesItOffTheMapAndKeepsItsLine() async throws {
        let (sandbox, model) = try await map()
        model.selection = .thought("need-to-tell-her-by-tuesday")
        model.pending = .confirmingSettle("need-to-tell-her-by-tuesday", .done)

        await model.perform(.settle(id: "need-to-tell-her-by-tuesday", as: .done, on: "2026-11-10"))

        #expect(model.pending == nil)
        #expect(model.selection == nil)
        #expect(!model.graph.nodes.contains { $0.id == "need-to-tell-her-by-tuesday" })
        #expect(sandbox.store.loadSnapshot().thoughts["need-to-tell-her-by-tuesday"] == nil)
        #expect(sandbox.store.loadPins().settled(forLine: "Need to tell her by Tuesday") == .done)

        // The line is still on its day, and on Meera's panel, now marked done.
        #expect(model.dayDetail(MemoryWeek.sunday.id)?.lines.last == MapTaggedLine(tag: "done", quote: "Need to tell her by Tuesday."))
        #expect(model.thoughtDetail("meera")?.days.first?.lines.last?.tag == "done")
        // Sunday is still a day on the map: it touched Meera and the pricing page.
        #expect(model.graph.days.count == 4)
    }

    @Test func notDoingItIsRecordedAsThat() async throws {
        let (sandbox, model) = try await map()

        await model.perform(.settle(id: "i-said-i-needed-to-think-about-it", as: .dropped, on: "2026-11-10"))

        #expect(sandbox.store.loadPins().settled(forLine: "I said I needed to think about it.") == .dropped)
        #expect(model.dayDetail(MemoryWeek.friday.id)?.lines.last?.tag == "not doing it")
        // Nothing was sent anywhere to do this.
        #expect(sandbox.store.loadSnapshot().thoughts.count == 7)
    }

    @Test func theMapReadsTheDaysLinesFromTheMemoryFolder() async throws {
        let (_, model) = try await map()

        #expect(model.dayLines.count == 4)
        #expect(model.thoughtDetail("meera")?.counted.count == 2)
        #expect(model.pins.isEmpty)
    }
}

/// Pictures of memory in the shape of a journal, drawn by the app's own code from the made-up week.
final class JournalMapSnapshotTests: XCTestCase {

    private let windowSize = CGSize(width: 1100, height: 640)

    @MainActor
    private func model(pins: Pins = Pins()) throws -> MapModel {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        var memory = try MemoryWeek.read().memory
        MemoryFixes.enforce(pins, on: &memory)
        model.show(memory: memory, dayLines: try MemoryWeek.dayLines(), pins: pins)
        return model
    }

    @MainActor
    private func picture(_ model: MapModel, named name: String, dark: Bool) throws {
        let screen = MapScreen(model: model, style: MapStyle(fontName: "Lato-Regular", isLight: !dark), emptyBecause: .waiting, onClose: {}, onOpenEntry: { _ in })
        attach(try renderOffscreen(screen, size: windowSize, dark: dark), named: name)
    }

    @MainActor
    func testTheWeekInLightAndDark() throws {
        let model = try model()
        model.fit(in: windowSize)

        try picture(model, named: "journal-map-light", dark: false)
        try picture(model, named: "journal-map-dark", dark: true)
        XCTAssertEqual(model.graph.thoughts.count, 8)
    }

    @MainActor
    func testAPersonsPanel() throws {
        let model = try model()
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        model.selection = .thought("meera")

        try picture(model, named: "journal-panel-person-light", dark: false)
        try picture(model, named: "journal-panel-person-dark", dark: true)
    }

    @MainActor
    func testWhatHelpedAndWhatIsStillOpen() throws {
        let model = try model()
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))

        model.selection = .thought("a-run-before-work")
        try picture(model, named: "journal-panel-helped", dark: false)

        model.selection = .thought("need-to-tell-her-by-tuesday")
        try picture(model, named: "journal-panel-open", dark: false)

        model.pending = .confirmingSettle("need-to-tell-her-by-tuesday", .done)
        try picture(model, named: "journal-panel-open-confirming-done", dark: true)
    }

    @MainActor
    func testADaysPanelBeforeAndAfterSomethingIsMarkedDone() throws {
        let open = try model()
        open.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        open.selection = .day(MemoryWeek.sunday.id)
        try picture(open, named: "journal-panel-day", dark: false)

        var pins = Pins()
        pins.deletions = [Pins.Deletion(id: "need-to-tell-her-by-tuesday", label: "Need to tell her by Tuesday", settled: "done", on: "2026-11-10")]
        let done = try model(pins: pins)
        done.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        done.selection = .day(MemoryWeek.sunday.id)
        try picture(done, named: "journal-panel-day-done", dark: false)
        XCTAssertEqual(done.dayDetail(MemoryWeek.sunday.id)?.lines.last?.tag, "done")
    }
}
