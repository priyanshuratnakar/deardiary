//
//  MemoryMapTests.swift
//  freewriteTests
//
//  Checks what the second round added to the map: days as small dots, the
//  layout that gives each busy thought its own fan of days, linking by
//  dragging one thought onto another, "Find", and what the empty map says.
//  Everything uses the made-up week or a made-up crowd.
//

import CoreGraphics
import Foundation
import Testing
@testable import freewrite

@MainActor
private func weekModel(size: CGSize) throws -> MapModel {
    let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
    let built = try MemoryWeek.built()
    var summaries: [UUID: String] = [:]
    for digest in built.digests {
        summaries[digest.entryID] = digest.summary
    }
    model.show(memory: built.memory, summaries: summaries)
    model.fit(in: size)
    return model
}

@MainActor
private func point(_ id: String, in model: MapModel, size: CGSize) throws -> CGPoint {
    let node = try #require(model.graph.nodes.first { $0.id == id })
    return model.screenPoint(node.position, in: size)
}

// MARK: - The layout

@Suite struct FanLayoutTests {

    private func distance(_ a: GraphNode, _ b: GraphNode) -> Double {
        Double(hypot(a.position.x - b.position.x, a.position.y - b.position.y))
    }

    private func settledCrowd() -> MemoryGraph {
        let built = GraphBuilder.build(from: MapFixtures.crowd(count: 120), saved: [:])
        return GraphLayout.settle(built.graph, moving: built.unplaced)
    }

    @Test func everyDaySitsCloseToAThoughtItTouched() throws {
        let graph = settledCrowd()
        let byID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        var nearest: [Double] = []
        for day in graph.days {
            let thoughts = (graph.neighbours[day.id] ?? []).compactMap { byID[$0] }
            nearest.append(try #require(thoughts.map { distance(day, $0) }.min()))
        }

        // Most days sit within a short reach of one of their thoughts; none wanders far off.
        let sorted = nearest.sorted()
        #expect(sorted[sorted.count / 2] < 110, "median \(sorted[sorted.count / 2])")
        #expect(sorted[sorted.count * 9 / 10] < 220, "ninth tenth \(sorted[sorted.count * 9 / 10])")
    }

    @Test func theThoughtsThatKeepComingBackEachGetTheirOwnPartOfTheMap() {
        // A journal kept for 200 days, where a dozen thoughts recur and most days touch two or three of them.
        let built = GraphBuilder.build(from: MapFixtures.journal(days: 200), saved: [:])
        let graph = GraphLayout.settle(built.graph, moving: built.unplaced)
        let busiest = graph.thoughts.sorted { ($0.weight, $1.id) > ($1.weight, $0.id) }.prefix(6)

        // Days pull them together; without the long push between busy thoughts they would all sit in the middle.
        for first in busiest {
            for second in busiest where first.id < second.id {
                // At least their own two sizes again between them.
                let room = Double(first.radius + second.radius) * 2
                #expect(distance(first, second) > room, "\(first.label) and \(second.label) are \(distance(first, second)) apart")
            }
        }
    }

    @Test func noTwoDotsOverlapWhetherThoughtsOrDays() {
        let graph = settledCrowd()
        var overlaps = 0
        for (index, first) in graph.nodes.enumerated() {
            for second in graph.nodes[(index + 1)...] where distance(first, second) < Double(first.radius + second.radius) {
                overlaps += 1
            }
        }
        #expect(overlaps == 0)
        #expect(graph.nodes.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }

    @Test func theSameMemoryAlwaysGivesTheSamePicture() {
        #expect(settledCrowd() == settledCrowd())
    }

    @Test func aNewDayIsPlacedBesideItsThoughtsWithoutMovingAnythingElse() throws {
        var memory = try MemoryWeek.built().memory
        let first = GraphBuilder.build(from: memory, saved: [:])
        let before = GraphLayout.settle(first.graph, moving: first.unplaced)
        let saved = Dictionary(uniqueKeysWithValues: before.nodes.map { ($0.id, $0.position) })

        // A new entry mentions Meera and running.
        let newEntry = UUID()
        for id in ["meera", "running"] {
            memory.thoughts[id]?.evidence.append(Evidence(entryID: newEntry, date: "2026-11-10", quote: "A made-up line about \(id)."))
        }
        let second = GraphBuilder.build(from: memory, saved: saved)
        let after = GraphLayout.settle(second.graph, moving: second.unplaced)

        #expect(second.unplaced == [GraphNode.dayID(newEntry)])
        for node in before.nodes {
            #expect(after.nodes.first { $0.id == node.id }?.position == node.position)
        }
        let day = try #require(after.days.first { $0.entryID == newEntry })
        let meera = try #require(after.nodes.first { $0.id == "meera" })
        let running = try #require(after.nodes.first { $0.id == "running" })
        // It lands no further from either than they are from each other, plus a little.
        #expect(distance(day, meera) < distance(meera, running) + 80)
        #expect(distance(day, running) < distance(meera, running) + 80)
    }

    @Test func aBigMemorySettlesQuickly() {
        // 300 thoughts and about 240 days: a couple of years of regular writing.
        let built = GraphBuilder.build(from: MapFixtures.crowd(count: 300), saved: [:])
        #expect(built.graph.nodes.count > 500)

        let elapsed = ContinuousClock().measure {
            _ = GraphLayout.settle(built.graph, moving: built.unplaced)
        }

        // Generous, because tests run a slower, unoptimised build. It happens once, off the main thread.
        #expect(elapsed < .seconds(8), "took \(elapsed)")
    }
}

// MARK: - Days on the map

@MainActor
@Suite struct MapDayTests {

    private let size = CGSize(width: 1100, height: 600)
    private var monday: String { GraphNode.dayID(MemoryWeek.monday.id) }

    @Test func clickingADaySelectsItAndShowsWhatItTouched() throws {
        let model = try weekModel(size: size)

        model.tap(at: try point(monday, in: model, size: size), in: size)

        #expect(model.selection == .day(MemoryWeek.monday.id))
        let detail = try #require(model.dayDetail(MemoryWeek.monday.id))
        #expect(detail.date == "2026-11-02")
        #expect(detail.summary?.isEmpty == false)
        #expect(detail.thoughts.map(\.label) == ["Meera", "Saying yes under pressure", "The launch", "Trouble sleeping"])
        #expect(detail.thoughts.first { $0.thoughtID == "trouble-sleeping" }?.quotes == ["Couldn’t sleep again."])
        #expect(detail.thoughts.allSatisfy { !$0.quotes.isEmpty })
        #expect(model.dayDetail(UUID()) == nil)
    }

    @Test func aSelectedDayAndTheThoughtsItTouchedStandOut() throws {
        let model = try weekModel(size: size)
        model.selection = .day(MemoryWeek.monday.id)

        let strong = model.graph.nodes.filter { model.emphasis(for: $0) == 1 }.map(\.id)

        #expect(Set(strong) == [monday, "meera", "saying-yes-under-pressure", "the-launch", "trouble-sleeping"])
        // Its own lines are at full strength and the others are faded.
        for edge in model.graph.edges {
            #expect(model.emphasis(for: edge) == (edge.first == monday || edge.second == monday ? 1 : 0.2))
        }
    }

    @Test func aDayIsOnlyNamedWhileItIsPointedAtOrSelected() throws {
        let model = try weekModel(size: size)
        func names() -> [String] {
            model.placedLabels(in: size, fontName: "Lato-Regular").map(\.label)
        }

        #expect(names().count == 7)
        #expect(!names().contains("Monday 2 November 2026"))

        model.hover(at: try point(monday, in: model, size: size), in: size)
        #expect(names().contains("Monday 2 November 2026"))

        model.hover(at: nil, in: size)
        model.selection = .day(MemoryWeek.monday.id)
        #expect(names().contains("Monday 2 November 2026"))
    }

    @Test func theLineFromADayToAThoughtCannotBeOpenedButALinkBetweenThoughtsCan() throws {
        let model = try weekModel(size: size)
        let day = try point(monday, in: model, size: size)
        let launch = try point("the-launch", in: model, size: size)

        // Half-way along the line from Monday's dot to "The launch", if no dot sits there.
        let middle = CGPoint(x: (day.x + launch.x) / 2, y: (day.y + launch.y) / 2)
        if model.thought(at: middle, in: size) == nil {
            #expect(model.link(at: middle, in: size) == nil || model.link(at: middle, in: size)?.contains("day:") == false)
        }
        #expect(model.graph.edges.filter(\.isDayLink).allSatisfy { edge in
            let a = model.graph.nodes.first { $0.id == edge.first }!, b = model.graph.nodes.first { $0.id == edge.second }!
            let mid = model.screenPoint(CGPoint(x: (a.position.x + b.position.x) / 2, y: (a.position.y + b.position.y) / 2), in: size)
            return model.link(at: mid, in: size) != edge.id
        })
    }

    @Test func aDayThatIsGoneFromMemoryIsNoLongerSelected() async throws {
        let sandbox = MemorySandbox()
        let built = try MemoryWeek.built()
        try sandbox.store.write(built.memory, replacing: MemorySnapshot())
        let model = MapModel(store: sandbox.store)
        await model.load()
        model.selection = .day(MemoryWeek.wednesday.id)

        // Wednesday's entry is deleted, so nothing in memory comes from it any more.
        var memory = built.memory
        MemoryApplier.remove(entryID: MemoryWeek.wednesday.id, from: &memory)
        try sandbox.store.write(memory, replacing: built.memory)
        await model.load()

        #expect(model.selection == nil)
        #expect(model.graph.days.count == 3)
    }

    @Test func whileAnotherThoughtIsBeingPickedAClickOnADayIsPassedOver() throws {
        let model = try weekModel(size: size)
        model.selection = .thought("arjun")
        model.pending = .pickingMergeTarget(source: "arjun")

        model.tap(at: try point(monday, in: model, size: size), in: size)
        #expect(model.pending == .pickingMergeTarget(source: "arjun"))
        #expect(model.selection == .thought("arjun"))

        model.tap(at: try point("meera", in: model, size: size), in: size)
        #expect(model.pending == .confirmingMerge(source: "arjun", target: "meera"))
    }

    @Test func theCountInTheBarSaysHowMuchIsOnTheMap() throws {
        let model = try weekModel(size: size)
        #expect(model.countLine == "7 thoughts · 4 days")

        model.show(memory: MemorySnapshot())
        #expect(model.countLine == nil)
    }
}

// MARK: - Linking by dragging

@MainActor
@Suite struct MapDragToLinkTests {

    @Test func droppingOneThoughtOnAnotherAsksHowTheyAreLinkedAndPutsTheDotBack() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        let home = try #require(model.graph.nodes.first { $0.id == "running" }?.position)
        let from = try map.point("running")
        let to = try map.point("trouble-sleeping")

        model.drag(from: from, to: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2), in: map.size, isFirstChange: true)
        #expect(model.draggedThought == "running")
        #expect(model.dropTarget == nil)

        model.drag(from: from, to: to, in: map.size, isFirstChange: false)
        #expect(model.dropTarget == "trouble-sleeping")
        #expect(model.dragStart == home)

        model.endDrag()

        // Not a move: the dot is back where it was, and the panel asks for the reason.
        #expect(model.graph.nodes.first { $0.id == "running" }?.position == home)
        #expect(model.selection == .thought("running"))
        #expect(model.pending == .reasonForLink(source: "running", target: "trouble-sleeping"))
        #expect(model.draggedThought == nil && model.dropTarget == nil)
        #expect(map.pins.isEmpty)

        await model.perform(.addLink(from: "running", to: "trouble-sleeping", reason: "helps with"))

        #expect(model.graph.edges.contains { $0.id == GraphEdge.id("running", "trouble-sleeping") && !$0.isDayLink })
        #expect(map.onDisk.thoughts["running"]?.userLinks == [UserLink(target: "trouble-sleeping", reason: "helps with")])
    }

    @Test func movingAwayAgainBeforeLettingGoIsJustAMove() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        let from = try map.point("running")
        let to = try map.point("trouble-sleeping")

        model.drag(from: from, to: to, in: map.size, isFirstChange: true)
        #expect(model.dropTarget == "trouble-sleeping")
        // Carried on past it, to an empty corner.
        let corner = CGPoint(x: 30, y: 30)
        model.drag(from: from, to: corner, in: map.size, isFirstChange: false)
        #expect(model.dropTarget == nil)
        model.endDrag()

        #expect(model.pending == nil)
        let moved = try #require(model.graph.nodes.first { $0.id == "running" })
        let landed = model.screenPoint(moved.position, in: map.size)
        #expect(abs(landed.x - corner.x) < 0.5 && abs(landed.y - corner.y) < 0.5)
    }

    @Test func aDayDroppedOnAThoughtIsOnlyMovedAndAThoughtDroppedOnADayIsToo() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        let monday = GraphNode.dayID(MemoryWeek.monday.id)

        model.drag(from: try map.point(monday), to: try map.point("arjun"), in: map.size, isFirstChange: true)
        #expect(model.dropTarget == nil)
        model.endDrag()
        #expect(model.pending == nil)

        let wednesday = GraphNode.dayID(MemoryWeek.wednesday.id)
        model.drag(from: try map.point("the-pricing-page"), to: try map.point(wednesday), in: map.size, isFirstChange: true)
        #expect(model.dropTarget == nil)
        model.endDrag()
        #expect(model.pending == nil)
        #expect(map.pins.isEmpty)
    }
}

// MARK: - Find

@MainActor
@Suite struct MapFindTests {

    private let size = CGSize(width: 1100, height: 600)

    @Test func typingFindsThoughtsByNameOrOtherNameWhateverTheCapitals() throws {
        let model = try weekModel(size: size)
        model.isFinding = true

        model.query = "MEER"
        #expect(model.matches.map(\.id) == ["meera"])
        #expect(model.findSummary == "1 thought")

        // "can't say no" is another name for "Saying yes under pressure".
        model.query = "say no"
        #expect(model.matches.map(\.id) == ["saying-yes-under-pressure"])

        // The most recurring come first.
        model.query = "the"
        #expect(model.matches.map(\.id) == ["the-launch", "the-pricing-page"])
        #expect(model.findSummary == "2 thoughts")

        model.query = "zzz"
        #expect(model.matches.isEmpty)
        #expect(model.findSummary == "No thought by that name")

        // Days are not thoughts, so a date finds nothing.
        model.query = "Monday"
        #expect(model.matches.isEmpty)
    }

    @Test func nothingIsFadedUntilSomethingIsTyped() throws {
        let model = try weekModel(size: size)
        model.isFinding = true

        #expect(model.isSearching == false)
        #expect(model.findSummary == nil)
        #expect(model.graph.nodes.allSatisfy { model.emphasis(for: $0) == 1 })

        model.query = "   "
        #expect(model.isSearching == false)
    }

    @Test func whatMatchesStaysBrightAndIsNamedAndTheRestFades() throws {
        let model = try weekModel(size: size)
        model.isFinding = true
        model.query = "sle"

        for node in model.graph.nodes {
            #expect(model.emphasis(for: node) == (node.id == "trouble-sleeping" ? 1 : 0.18))
        }
        #expect(model.graph.edges.allSatisfy { model.emphasis(for: $0) == 0.25 })
        let label = try #require(model.placedLabels(in: size, fontName: "Lato-Regular").first { $0.thoughtID == "trouble-sleeping" })
        #expect(label.isFocus)
    }

    @Test func returnOpensTheFirstMatchAndBringsItIntoView() throws {
        let model = try weekModel(size: size)
        // The map has been dragged far to one side.
        model.pan = CGSize(width: 4000, height: 3000)
        model.isFinding = true
        model.query = "meera"

        model.openFirstMatch(in: size)

        #expect(model.selection == .thought("meera"))
        let where_ = try point("meera", in: model, size: size)
        #expect(CGRect(origin: .zero, size: size).contains(where_))
    }

    @Test func returnWithNoMatchDoesNothing() throws {
        let model = try weekModel(size: size)
        model.isFinding = true
        model.query = "zzz"

        model.openFirstMatch(in: size)

        #expect(model.selection == nil)
    }

    @Test func typingAgainClosesWhatWasOpenAndClosingFindForgetsWhatWasTyped() throws {
        let model = try weekModel(size: size)
        model.isFinding = true
        model.query = "meera"
        model.openFirstMatch(in: size)
        #expect(model.selection == .thought("meera"))

        model.query = "meer"
        #expect(model.selection == nil)

        model.stopFinding()
        #expect(model.isFinding == false)
        #expect(model.query == "")
        #expect(model.graph.nodes.allSatisfy { model.emphasis(for: $0) == 1 })
    }
}

// MARK: - What the empty map says

@Suite struct MapEmptyReasonTests {

    @Test func itSaysTheRightThingForWhereSetupHasGotTo() {
        let box = SettingsBox()
        let settings = box.settings()

        // Nothing set up at all.
        #expect(MapEmptyReason.current(settings) == .noAI)

        // AI on, but no key yet.
        settings.aiEnabled = true
        #expect(MapEmptyReason.current(settings) == .noAI)

        // A service is ready, memory is still off.
        settings.saveAPIKey("made-up-key-for-tests")
        #expect(MapEmptyReason.current(settings) == .memoryOff)

        settings.memoryEnabled = true
        #expect(MapEmptyReason.current(settings) == .waiting)
    }

    @Test func eachReasonIsOnePlainLineAndPointsAtSettingsOnlyWhenThatIsTheNextStep() {
        #expect(MapEmptyReason.noAI.settingsWord == "Set it up in Settings")
        #expect(MapEmptyReason.memoryOff.settingsWord == "Open Settings")
        #expect(MapEmptyReason.waiting.settingsWord == nil)
        for reason in [MapEmptyReason.noAI, .memoryOff, .waiting] {
            #expect(reason.line.hasSuffix("."))
            #expect(!reason.line.contains("\n"))
        }
    }
}
