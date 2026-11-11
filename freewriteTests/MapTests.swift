//
//  MapTests.swift
//  freewriteTests
//
//  Checks the map without looking at it: how the graph is built from memory,
//  where the dots are placed, that positions are remembered, what a click
//  selects, and what the detail panel shows. Uses made-up memory only.
//

import Foundation
import CoreGraphics
import Testing
@testable import freewrite

@Suite struct GraphBuilderTests {

    @Test func everyThoughtIsADotSizedByHowManyEntriesTouchedIt() throws {
        let graph = GraphBuilder.build(from: try MemoryWeek.built().memory, saved: [:]).graph
        let weights = Dictionary(uniqueKeysWithValues: graph.thoughts.map { ($0.id, $0.weight) })

        #expect(weights == [
            "meera": 3,
            "trouble-sleeping": 3,
            "saying-yes-under-pressure": 2,
            "the-launch": 2,
            "the-pricing-page": 2,
            "running": 1,
            "arjun": 1,
        ])
        #expect(graph.nodes.first { $0.id == "meera" }?.kind == .person)
        #expect(graph.nodes.first { $0.id == "meera" }?.label == "Meera")
    }

    @Test func everyLinkIsOneLineWithItsReason() throws {
        let graph = GraphBuilder.build(from: try MemoryWeek.built().memory, saved: [:]).graph
        let links = graph.edges.filter { !$0.isDayLink }

        #expect(links.map(\.id) == [
            "meera|saying-yes-under-pressure",
            "meera|the-pricing-page",
            "saying-yes-under-pressure|trouble-sleeping",
        ])
        #expect(links[1].reasons == ["asked for by"])
        #expect(graph.edges.allSatisfy { $0.count == 1 })
        #expect(Set((graph.neighbours["meera"] ?? []).filter { !$0.hasPrefix("day:") }) == ["saying-yes-under-pressure", "the-pricing-page"])
    }

    // MARK: - Days

    @Test func everyEntryMemoryHasReadIsASmallDotJoinedToTheThoughtsItTouched() throws {
        let graph = GraphBuilder.build(from: try MemoryWeek.built().memory, saved: [:]).graph

        #expect(graph.thoughts.count == 7)
        #expect(graph.days.map(\.entryID) == MemoryWeek.entries.map(\.id))
        #expect(graph.days.map(\.date) == ["2026-11-02", "2026-11-04", "2026-11-06", "2026-11-08"])
        #expect(graph.days.first?.label == "Monday 2 November 2026")
        #expect(graph.days.allSatisfy { $0.kind == nil && $0.isDay })
        #expect(graph.thoughts.allSatisfy { $0.kind != nil && !$0.isDay })

        // Monday's entry touched four thoughts, so its dot has four lines.
        let monday = GraphNode.dayID(MemoryWeek.monday.id)
        #expect(graph.neighbours[monday] == ["meera", "saying-yes-under-pressure", "the-launch", "trouble-sleeping"])
        #expect(graph.days.first?.weight == 4)
        let dayLines = graph.edges.filter(\.isDayLink)
        #expect(dayLines.allSatisfy { $0.reasons.isEmpty && $0.count == 1 })
        // One line for each thought and entry pair, however many lines were quoted.
        #expect(dayLines.count == graph.thoughts.map(\.weight).reduce(0, +))
    }

    @Test func aDayIsAlwaysSmallAndAThoughtIsNeverSmallerThanADay() throws {
        let graph = GraphBuilder.build(from: try MemoryWeek.built().memory, saved: [:]).graph
        let dayRadius = try #require(graph.days.first?.radius)

        #expect(graph.days.allSatisfy { $0.radius == dayRadius })
        #expect(graph.thoughts.allSatisfy { $0.radius > dayRadius * 1.5 })
    }

    @Test func whenAThoughtGoesItsDaysStayOnlyWhileAnotherThoughtStillUsesThem() throws {
        var memory = try MemoryWeek.built().memory
        // Friday's entry touched Meera, the pricing page, saying yes and trouble sleeping.
        let before = GraphBuilder.build(from: memory, saved: [:]).graph.days.count
        for id in memory.thoughts.keys where id != "running" && id != "arjun" {
            memory.thoughts[id] = nil
        }

        let graph = GraphBuilder.build(from: memory, saved: [:]).graph

        #expect(before == 4)
        // Only Wednesday's entry mentioned running and Arjun.
        #expect(graph.days.map(\.date) == ["2026-11-04"])
        #expect(graph.edges.count == 2)
    }

    @Test func severalLinksBetweenTheSameTwoThoughtsAreOneLine() throws {
        var memory = try MemoryWeek.built().memory
        memory.thoughts["meera"]?.links.append(ThoughtLink(
            target: "saying-yes-under-pressure",
            reason: "hard to refuse",
            entryID: MemoryWeek.friday.id,
            date: "2026-11-06",
            quote: "Meera asked if I could also take the pricing page."
        ))

        let edge = try #require(GraphBuilder.build(from: memory, saved: [:]).graph.edges.first { $0.id == "meera|saying-yes-under-pressure" })

        #expect(edge.count == 2)
        #expect(Set(edge.reasons) == ["shows up around", "hard to refuse"])
    }

    @Test func aLinkToAThoughtThatIsGoneIsNotDrawn() throws {
        var memory = try MemoryWeek.built().memory
        memory.thoughts["meera"] = nil

        let graph = GraphBuilder.build(from: memory, saved: [:]).graph

        #expect(graph.edges.filter { !$0.isDayLink }.map(\.id) == ["saying-yes-under-pressure|trouble-sleeping"])
        #expect(graph.edges.allSatisfy { !$0.id.contains("meera") })
    }

    @Test func rememberedPositionsAreUsedAndTheRestAreReportedAsNew() throws {
        let saved = ["meera": CGPoint(x: 40, y: -25)]

        let built = GraphBuilder.build(from: try MemoryWeek.built().memory, saved: saved)

        #expect(built.graph.nodes.first { $0.id == "meera" }?.position == CGPoint(x: 40, y: -25))
        // Six thoughts and four days have no place yet.
        #expect(built.unplaced.count == 10)
        #expect(!built.unplaced.contains("meera"))
    }

    @Test func dotsGrowGentlyWithRecurrenceUpToALimit() {
        func radius(_ weight: Int) -> CGFloat {
            GraphNode(id: "x", label: "X", kind: .theme, weight: weight, position: .zero).radius
        }

        #expect(radius(1) < radius(4))
        #expect(radius(4) < radius(16))
        // A thought that came up once is a small dot; one that keeps coming back is a big one.
        #expect(radius(1) >= 5)
        #expect(radius(1) < 6)
        #expect(radius(40) > radius(1) * 3)
        #expect(radius(10_000) == 22)
    }
}

@Suite struct GraphLayoutTests {

    private func settled(_ memory: MemorySnapshot) -> MemoryGraph {
        let built = GraphBuilder.build(from: memory, saved: [:])
        return GraphLayout.settle(built.graph, moving: built.unplaced)
    }

    private func distance(_ a: GraphNode, _ b: GraphNode) -> CGFloat {
        hypot(a.position.x - b.position.x, a.position.y - b.position.y)
    }

    @Test func theSameMemoryAlwaysGivesTheSamePicture() throws {
        let memory = try MemoryWeek.built().memory

        #expect(settled(memory) == settled(memory))
        #expect(settled(MapFixtures.crowd(count: 60)) == settled(MapFixtures.crowd(count: 60)))
    }

    @Test func noTwoDotsOverlapAndEveryPositionIsARealNumber() {
        let graph = settled(MapFixtures.crowd(count: 120))

        for node in graph.nodes {
            #expect(node.position.x.isFinite && node.position.y.isFinite)
        }
        for (index, first) in graph.nodes.enumerated() {
            for second in graph.nodes[(index + 1)...] {
                #expect(distance(first, second) >= first.radius + second.radius + 8, "\(first.id) and \(second.id) are too close")
            }
        }
    }

    @Test func linkedThoughtsSitCloserThanThoughtsInGeneral() {
        let graph = settled(MapFixtures.crowd(count: 120))
        let byID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })

        let linked = graph.edges.map { distance(byID[$0.first]!, byID[$0.second]!) }
        var all: [CGFloat] = []
        for (index, first) in graph.nodes.enumerated() {
            for second in graph.nodes[(index + 1)...] {
                all.append(distance(first, second))
            }
        }

        let linkedAverage = linked.reduce(0, +) / CGFloat(linked.count)
        let overallAverage = all.reduce(0, +) / CGFloat(all.count)
        #expect(linkedAverage < overallAverage * 0.6)
    }

    @Test func aFreshMapIsCentredOnItsMiddle() throws {
        let graph = settled(try MemoryWeek.built().memory)
        let middleX = graph.nodes.map(\.position.x).reduce(0, +) / CGFloat(graph.nodes.count)
        let middleY = graph.nodes.map(\.position.y).reduce(0, +) / CGFloat(graph.nodes.count)

        #expect(abs(middleX) < 0.001)
        #expect(abs(middleY) < 0.001)
    }

    @Test func dotsThatAlreadyHaveAPlaceAreNotMovedAndANewOneLandsNearWhatItIsLinkedTo() throws {
        var memory = try MemoryWeek.built().memory
        let first = settled(memory)
        let saved = Dictionary(uniqueKeysWithValues: first.nodes.map { ($0.id, $0.position) })

        // A new thought arrives, linked to Meera.
        memory.thoughts["the-offsite"] = Thought(
            id: "the-offsite",
            label: "The offsite",
            kind: .event,
            evidence: [Evidence(entryID: MemoryWeek.sunday.id, date: "2026-11-08", quote: "Slept badly.")],
            links: [ThoughtLink(target: "meera", reason: "planned by", entryID: MemoryWeek.sunday.id, date: "2026-11-08", quote: "Slept badly.")]
        )
        let built = GraphBuilder.build(from: memory, saved: saved)
        #expect(built.unplaced == ["the-offsite"])
        let second = GraphLayout.settle(built.graph, moving: built.unplaced)

        for node in first.nodes {
            #expect(second.nodes.first { $0.id == node.id }?.position == node.position, "\(node.id) moved")
        }
        let offsite = try #require(second.nodes.first { $0.id == "the-offsite" })
        let meera = try #require(second.nodes.first { $0.id == "meera" })
        #expect(distance(offsite, meera) < 360)
        #expect(distance(offsite, meera) >= offsite.radius + meera.radius + 8)
    }

    @Test func withNothingToPlaceNothingChanges() throws {
        let graph = settled(try MemoryWeek.built().memory)

        #expect(GraphLayout.settle(graph, moving: []) == graph)
        #expect(GraphLayout.settle(MemoryGraph(), moving: ["anything"]) == MemoryGraph())
    }

    @Test func threeHundredThoughtsSettleQuickly() {
        let built = GraphBuilder.build(from: MapFixtures.crowd(count: 300), saved: [:])

        let elapsed = ContinuousClock().measure {
            _ = GraphLayout.settle(built.graph, moving: built.unplaced)
        }

        // Generous, because tests run a slower, unoptimised build. It happens once, off the main thread.
        #expect(elapsed < .seconds(8), "took \(elapsed)")
    }
}

@Suite struct GraphFileTests {

    /// A memory store in a folder that exists only for one test.
    private final class Sandbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Freewrite", isDirectory: true)

        var store: MemoryStore { MemoryStore(root: root) }

        deinit {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
    }

    private func graph() throws -> MemoryGraph {
        let built = GraphBuilder.build(from: try MemoryWeek.built().memory, saved: [:])
        return GraphLayout.settle(built.graph, moving: built.unplaced)
    }

    @Test func positionsAreSavedInGraphJSONAndReadBack() throws {
        let sandbox = Sandbox()
        let graph = try graph()

        try sandbox.store.saveGraph(graph)
        let positions = sandbox.store.loadGraphPositions()

        #expect(sandbox.store.graphURL.path.hasSuffix("/memory/graph.json"))
        // Seven thoughts and four days.
        #expect(positions.count == 11)
        for node in graph.nodes {
            let saved = try #require(positions[node.id])
            #expect(abs(saved.x - node.position.x) <= 0.05)
            #expect(abs(saved.y - node.position.y) <= 0.05)
        }
    }

    @Test func theFileIsPlainJSONWithTheGraphInIt() throws {
        let sandbox = Sandbox()
        try sandbox.store.saveGraph(try graph())

        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: sandbox.store.graphURL)) as? [String: Any])
        let nodes = try #require(json["nodes"] as? [[String: Any]])
        let edges = try #require(json["edges"] as? [[String: Any]])

        #expect(json["version"] as? Int == 1)
        #expect(nodes.count == 11)
        #expect(Set(nodes[0].keys) == ["id", "label", "kind", "weight", "x", "y"])
        #expect(nodes.filter { $0["kind"] as? String == "day" }.count == 4)
        // Three links between thoughts, and a line for each thought and entry pair.
        #expect(edges.count == 3 + 14)
        #expect(Set(edges[0].keys) == ["from", "to", "count", "reasons"])
    }

    @Test func positionsSurviveARebuildAndGoWhenEverythingIsForgotten() throws {
        let sandbox = Sandbox()
        try sandbox.store.write(try MemoryWeek.built().memory, replacing: MemorySnapshot())
        try sandbox.store.saveGraph(try graph())

        sandbox.store.forgetAIBuilt()
        #expect(sandbox.store.loadGraphPositions().count == 11)

        sandbox.store.forgetEverything()
        #expect(sandbox.store.loadGraphPositions().isEmpty)
    }

    @Test func aMissingOrBrokenFileMeansNoRememberedPositions() throws {
        let sandbox = Sandbox()
        #expect(sandbox.store.loadGraphPositions().isEmpty)

        sandbox.store.ensureFolder()
        try "not json".write(to: sandbox.store.graphURL, atomically: true, encoding: .utf8)
        #expect(sandbox.store.loadGraphPositions().isEmpty)
    }
}

@MainActor
@Suite struct MapModelTests {

    private let size = CGSize(width: 1100, height: 600)

    /// A store in a throwaway folder, filled with the made-up week.
    private final class Sandbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Freewrite", isDirectory: true)

        var store: MemoryStore { MemoryStore(root: root) }

        init() throws {
            try store.write(try MemoryWeek.built().memory, replacing: MemorySnapshot())
        }

        deinit {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
    }

    private func weekModel() throws -> MapModel {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        model.show(memory: try MemoryWeek.built().memory)
        model.fit(in: size)
        return model
    }

    private func screenPoint(_ id: String, in model: MapModel) throws -> CGPoint {
        let node = try #require(model.graph.nodes.first { $0.id == id })
        return model.screenPoint(node.position, in: size)
    }

    // MARK: - Loading and remembering

    @Test func openingTheMapPlacesTheDotsAndRemembersWhereTheyAre() async throws {
        let sandbox = try Sandbox()
        let first = MapModel(store: sandbox.store)
        #expect(first.isLoading)

        await first.load()

        #expect(first.isLoading == false)
        #expect(first.graph.thoughts.count == 7)
        #expect(FileManager.default.fileExists(atPath: sandbox.store.graphURL.path))

        // Opening it again puts every dot back in the same place.
        let second = MapModel(store: sandbox.store)
        await second.load()
        for node in first.graph.nodes {
            let again = try #require(second.graph.nodes.first { $0.id == node.id })
            #expect(abs(again.position.x - node.position.x) <= 0.05)
            #expect(abs(again.position.y - node.position.y) <= 0.05)
        }
    }

    @Test func aDraggedDotStaysWhereItWasLeft() async throws {
        let sandbox = try Sandbox()
        let model = MapModel(store: sandbox.store)
        await model.load()
        model.fit(in: size)

        let start = try screenPoint("running", in: model)
        let end = CGPoint(x: start.x + 120, y: start.y - 60)
        model.drag(from: start, to: CGPoint(x: start.x + 50, y: start.y - 20), in: size, isFirstChange: true)
        model.drag(from: start, to: end, in: size, isFirstChange: false)
        model.endDrag()

        let moved = model.mapPoint(end, in: size)
        #expect(model.graph.nodes.first { $0.id == "running" }?.position == moved)

        // It is written to graph.json, so it is still there next time.
        await waitUntil {
            guard let saved = sandbox.store.loadGraphPositions()["running"] else { return false }
            return abs(saved.x - moved.x) <= 0.05 && abs(saved.y - moved.y) <= 0.05
        }
        let reopened = MapModel(store: sandbox.store)
        await reopened.load()
        let position = try #require(reopened.graph.nodes.first { $0.id == "running" }?.position)
        #expect(abs(position.x - moved.x) <= 0.05)
        #expect(abs(position.y - moved.y) <= 0.05)
    }

    @Test func draggingEmptySpaceMovesTheMapNotADot() throws {
        let model = try weekModel()
        let before = model.graph
        let panBefore = model.pan

        model.drag(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 45, y: 25), in: size, isFirstChange: true)
        model.endDrag()

        #expect(model.graph == before)
        #expect(model.pan == CGSize(width: panBefore.width + 40, height: panBefore.height + 20))
    }

    @Test func fitBringsEveryDotIntoTheWindow() {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        model.show(memory: MapFixtures.crowd(count: 300))
        model.pan = CGSize(width: 5000, height: -3000)
        model.zoom = 3

        model.fit(in: size)

        for node in model.graph.nodes {
            let point = model.screenPoint(node.position, in: size)
            #expect(point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height, "\(node.id) is off screen")
        }
    }

    @Test func zoomStaysWithinSensibleLimits() throws {
        let model = try weekModel()

        model.pinch(100, isFirstChange: true)
        #expect(model.zoom == MapModel.zoomRange.upperBound)

        model.pinch(0.0001, isFirstChange: true)
        #expect(model.zoom == MapModel.zoomRange.lowerBound)
    }

    // MARK: - Clicking and hovering

    @Test func clickingADotALineOrEmptySpaceSelectsTheRightThing() throws {
        let model = try weekModel()
        let meera = try screenPoint("meera", in: model)
        let pricing = try screenPoint("the-pricing-page", in: model)

        model.tap(at: meera, in: size)
        #expect(model.selection == .thought("meera"))

        // A point on the line between Meera and the pricing page that no dot sits on.
        let steps = stride(from: 0.2, through: 0.8, by: 0.05).map { CGFloat($0) }
        let onTheLine = try #require(steps
            .map { CGPoint(x: meera.x + (pricing.x - meera.x) * $0, y: meera.y + (pricing.y - meera.y) * $0) }
            .first { model.thought(at: $0, in: size) == nil })
        model.tap(at: onTheLine, in: size)
        #expect(model.selection == .link("meera|the-pricing-page"))

        model.tap(at: CGPoint(x: 3, y: 3), in: size)
        #expect(model.selection == nil)
    }

    @Test func aDotIsEasierToHitThanItLooks() throws {
        let model = try weekModel()
        let node = try #require(model.graph.nodes.first { $0.id == "arjun" })
        let centre = model.screenPoint(node.position, in: size)
        let radius = model.screenRadius(node)

        #expect(model.thought(at: CGPoint(x: centre.x + radius + 5, y: centre.y), in: size) == "arjun")
        #expect(model.thought(at: CGPoint(x: centre.x + radius + 12, y: centre.y), in: size) == nil)
    }

    @Test func hoveringAThoughtMakesItAndItsLinksStandOut() throws {
        let model = try weekModel()
        func emphasis(_ id: String) -> Double {
            model.emphasis(for: model.graph.nodes.first { $0.id == id }!)
        }
        #expect(emphasis("running") == 1)

        model.hover(at: try screenPoint("meera", in: model), in: size)

        #expect(model.hoveredThought == "meera")
        #expect(emphasis("meera") == 1)
        #expect(emphasis("the-pricing-page") == 1)
        #expect(emphasis("saying-yes-under-pressure") == 1)
        #expect(emphasis("running") < 0.5)
        #expect(model.emphasis(for: model.graph.edges.first { $0.id == "meera|the-pricing-page" }!) == 1)
        #expect(model.emphasis(for: model.graph.edges.first { $0.id == "saying-yes-under-pressure|trouble-sleeping" }!) < 0.5)

        model.hover(at: nil, in: size)
        #expect(model.hoveredThought == nil)
        #expect(emphasis("running") == 1)
    }

    @Test func pointingAtAKindInTheLegendMakesThatKindStandOut() throws {
        let model = try weekModel()

        model.highlightedKind = .person

        for node in model.graph.nodes {
            #expect(model.emphasis(for: node) == (node.kind == .person ? 1 : 0.18))
        }
    }

    // MARK: - Names on the map

    @Test func aSmallMapNamesEveryThought() throws {
        let model = try weekModel()

        let labels = model.placedLabels(in: size, fontName: "Lato-Regular")

        #expect(Set(labels.map(\.label)) == ["Meera", "Trouble sleeping", "Saying yes under pressure", "The launch", "The pricing page", "Running", "Arjun"])
    }

    @Test func aCrowdedMapOnlyNamesWhatThereIsRoomForAndAlwaysTheMostRecurring() {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        model.show(memory: MapFixtures.crowd(count: 300))
        model.fit(in: size)

        let labels = model.placedLabels(in: size, fontName: "Lato-Regular")

        #expect(labels.count < 100)
        #expect(labels.count >= 10)

        // No two names sit on top of each other.
        let rects = labels.map { CGRect(x: $0.point.x - $0.size.width / 2, y: $0.point.y, width: $0.size.width, height: $0.size.height) }
        for (index, first) in rects.enumerated() {
            for second in rects[(index + 1)...] {
                #expect(!first.intersects(second))
            }
        }

        // The most recurring thought is named.
        let heaviest = model.graph.nodes.max { ($0.weight, $1.id) < ($1.weight, $0.id) }!
        #expect(labels.contains { $0.thoughtID == heaviest.id })

        // Zooming in makes room for more names.
        model.zoom = 2
        #expect(model.placedLabels(in: size, fontName: "Lato-Regular").count > 0)
    }

    // MARK: - The detail panel

    @Test func aThoughtShowsWhatItIsHowItShiftedAndTheLinesBehindItByDay() throws {
        let model = try weekModel()

        let detail = try #require(model.thoughtDetail("saying-yes-under-pressure"))

        #expect(detail.label == "Saying yes under pressure")
        #expect(detail.kind == .theme)
        #expect(detail.aliases == ["can't say no", "Saying yes"])
        #expect(detail.summary == "Agreeing in the moment and feeling sick about it afterwards.")
        #expect(detail.firstSeen == "2026-11-02")
        #expect(detail.lastSeen == "2026-11-06")
        #expect(detail.shifts == [MapThoughtDetail.Shift(date: "2026-11-06", note: "Held back from agreeing for the first time.")])
        // The most recent day first.
        #expect(detail.days == [
            MapDayQuotes(entryID: MemoryWeek.friday.id, date: "2026-11-06", quotes: ["First time I haven't just said yes."]),
            MapDayQuotes(entryID: MemoryWeek.monday.id, date: "2026-11-02", quotes: ["I said yes to everything she asked and then felt sick about it"]),
        ])
        // What the app can say by counting sits beside what the AI wrote before M14.
        #expect(detail.counted == ["In 2 entries, from Monday 2 November to Friday 6 November 2026."])
        // Links are shown from both ends: one it makes, one made to it.
        #expect(detail.connections.map(\.label) == ["Meera", "Trouble sleeping"])
        #expect(detail.connections.map(\.reasons) == [["shows up around"], ["follows"]])
        #expect(detail.connections.first?.linkID == "meera|saying-yes-under-pressure")
    }

    @Test func aLinkShowsWhyAndTheLinesThatShowIt() throws {
        let model = try weekModel()

        let detail = try #require(model.linkDetail("meera|the-pricing-page"))

        #expect(detail.firstLabel == "Meera")
        #expect(detail.secondLabel == "The pricing page")
        #expect(detail.reasons == ["asked for by"])
        #expect(detail.days == [
            MapDayQuotes(entryID: MemoryWeek.friday.id, date: "2026-11-06", quotes: ["Meera asked if I could also take the pricing page."]),
        ])
    }

    @Test func everyDayInTheDetailPointsAtARealEntry() throws {
        let model = try weekModel()
        let entryIDs = Set(MemoryWeek.entries.map(\.id))

        for node in model.graph.thoughts {
            let detail = try #require(model.thoughtDetail(node.id))
            #expect(!detail.days.isEmpty)
            #expect(detail.days.allSatisfy { entryIDs.contains($0.entryID) })
        }
        #expect(model.thoughtDetail("not-a-thought") == nil)
        #expect(model.linkDetail("not|a-link") == nil)
    }

    @Test func aSelectionThatNoLongerExistsIsDroppedOnReload() async throws {
        let sandbox = try Sandbox()
        let model = MapModel(store: sandbox.store)
        await model.load()
        model.selection = .thought("running")

        // The thought disappears from memory (for example its entry was deleted).
        var memory = sandbox.store.loadSnapshot()
        let before = memory
        memory.thoughts["running"] = nil
        try sandbox.store.write(memory, replacing: before)
        await model.load()

        #expect(model.selection == nil)
        #expect(model.graph.thoughts.count == 6)
    }
}
