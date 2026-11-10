//
//  MapFixTests.swift
//  freewriteTests
//
//  Checks the user's fixes as they are made on the map: rename, merge, link,
//  delete and remove link, each going through the same steps the panel does
//  and landing in the memory folder. Also draws the panel in each state.
//  Everything happens in a throwaway folder with the made-up week.
//

import XCTest
import SwiftUI
import Testing
@testable import freewrite

/// A throwaway memory folder holding the made-up week, and a map over it whose
/// fixes go through the real engine.
@MainActor
final class MapFixSandbox {
    let sandbox = MemorySandbox()
    let engine: MemoryEngine
    let model: MapModel
    let size = CGSize(width: 1100, height: 600)

    init() async throws {
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        let built = try MemoryWeek.built()
        try sandbox.store.write(built.memory, replacing: MemorySnapshot())
        for digest in built.digests {
            try sandbox.store.saveDigest(digest)
        }

        let engine = sandbox.engine(FakeProvider())
        self.engine = engine
        model = MapModel(store: sandbox.store, applyFix: { await engine.fix($0) })
        await model.load()
        model.fit(in: size)
    }

    func point(_ id: String) throws -> CGPoint {
        let node = try #require(model.graph.nodes.first { $0.id == id })
        return model.screenPoint(node.position, in: size)
    }

    var onDisk: MemorySnapshot { sandbox.store.loadSnapshot() }
    var pins: Pins { sandbox.store.loadPins() }
}

@MainActor
@Suite struct MapFixFlowTests {

    @Test func renamingAThoughtChangesItsNameOnTheMapAndOnDisk() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        model.selection = .thought("saying-yes-under-pressure")
        model.pending = .renaming("saying-yes-under-pressure")

        await model.perform(.rename(id: "saying-yes-under-pressure", to: "Agreeing too fast"))

        #expect(model.pending == nil)
        #expect(model.selection == .thought("saying-yes-under-pressure"))
        #expect(model.graph.nodes.first { $0.id == "saying-yes-under-pressure" }?.label == "Agreeing too fast")
        #expect(model.thoughtDetail("saying-yes-under-pressure")?.aliases.contains("Saying yes under pressure") == true)
        #expect(map.onDisk.thoughts["saying-yes-under-pressure"]?.label == "Agreeing too fast")
        #expect(map.pins.pinnedLabel(for: "saying-yes-under-pressure") == "Agreeing too fast")
    }

    @Test func mergingAsksForTheOtherThoughtThenASecondClick() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        model.selection = .thought("arjun")
        model.pending = .pickingMergeTarget(source: "arjun")

        // The click on Meera picks her as the target; it does not change what is selected.
        model.tap(at: try map.point("meera"), in: map.size)
        #expect(model.pending == .confirmingMerge(source: "arjun", target: "meera"))
        #expect(model.selection == .thought("arjun"))
        #expect(map.onDisk.thoughts["arjun"] != nil)

        await model.perform(.merge(from: "arjun", into: "meera"))

        #expect(model.pending == nil)
        #expect(model.selection == .thought("meera"))
        #expect(model.graph.nodes.count == 6)
        #expect(model.thoughtDetail("meera")?.aliases.contains("Arjun") == true)
        #expect(map.onDisk.thoughts["arjun"] == nil)
        #expect(map.pins.resolve("arjun") == "meera")
    }

    @Test func aClickOnEmptySpaceOrOnTheSameThoughtBacksOutOfPicking() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        model.selection = .thought("arjun")

        model.pending = .pickingMergeTarget(source: "arjun")
        model.tap(at: CGPoint(x: 3, y: 3), in: map.size)
        #expect(model.pending == nil)
        #expect(model.selection == .thought("arjun"))

        model.pending = .pickingLinkTarget(source: "arjun")
        model.tap(at: try map.point("arjun"), in: map.size)
        #expect(model.pending == nil)
        #expect(model.selection == .thought("arjun"))

        #expect(map.pins.isEmpty)
        #expect(model.graph.nodes.count == 7)
    }

    @Test func whileAnotherThoughtIsBeingPickedNoneIsFadedAndThenTheTwoStandOut() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        func strength(_ id: String) -> Double {
            model.graph.nodes.first { $0.id == id }.map { model.emphasis(for: $0) } ?? -1
        }

        // With a thought selected, the ones it is not linked to are faded.
        model.selection = .thought("arjun")
        #expect(strength("the-launch") < 1)

        // While picking, every thought can be clicked, so every thought is at full strength.
        model.pending = .pickingMergeTarget(source: "arjun")
        #expect(model.graph.nodes.allSatisfy { model.emphasis(for: $0) == 1 })
        #expect(model.placedLabels(in: map.size, fontName: "Lato-Regular").first { $0.thoughtID == "arjun" }?.isFocus == true)

        // Once the other thought is picked, the two stand out and the rest fade again.
        model.tap(at: try map.point("meera"), in: map.size)
        #expect(strength("arjun") == 1)
        #expect(strength("meera") == 1)
        #expect(strength("the-launch") < 1)
    }

    @Test func linkingAsksForTheOtherThoughtThenAReason() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        model.selection = .thought("running")
        model.pending = .pickingLinkTarget(source: "running")

        model.tap(at: try map.point("trouble-sleeping"), in: map.size)
        #expect(model.pending == .reasonForLink(source: "running", target: "trouble-sleeping"))
        #expect(model.selection == .thought("running"))

        await model.perform(.addLink(from: "running", to: "trouble-sleeping", reason: "helps with"))

        let linkID = GraphEdge.id("running", "trouble-sleeping")
        #expect(model.pending == nil)
        #expect(model.selection == .link(linkID))
        #expect(model.graph.edges.contains { $0.id == linkID })

        let detail = try #require(model.linkDetail(linkID))
        #expect(detail.reasons == ["helps with"])
        #expect(detail.linkedByYou == ["helps with"])
        #expect(detail.days.isEmpty)
        #expect(model.thoughtDetail("running")?.connections.map(\.thoughtID) == ["trouble-sleeping"])
        #expect(model.thoughtDetail("trouble-sleeping")?.connections.map(\.thoughtID).contains("running") == true)
        #expect(map.onDisk.thoughts["running"]?.userLinks == [UserLink(target: "trouble-sleeping", reason: "helps with")])
    }

    @Test func deletingAThoughtTakesItOffTheMapForGood() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        model.selection = .thought("running")
        model.pending = .confirmingDelete("running")

        await model.perform(.delete(id: "running"))

        #expect(model.pending == nil)
        #expect(model.selection == nil)
        #expect(model.graph.nodes.count == 6)
        #expect(map.onDisk.thoughts["running"] == nil)
        #expect(map.pins.isDeleted("running"))

        // Opening the map again does not bring it back.
        let again = MapModel(store: map.sandbox.store)
        await again.load()
        #expect(again.graph.nodes.contains { $0.id == "running" } == false)
    }

    @Test func removingALinkTakesTheLineAwayAndLeavesBothThoughts() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        let linkID = GraphEdge.id("meera", "the-pricing-page")
        model.selection = .link(linkID)
        model.pending = .confirmingRemoveLink(linkID)

        await model.perform(.removeLink("meera", "the-pricing-page"))

        #expect(model.pending == nil)
        #expect(model.selection == nil)
        #expect(model.graph.edges.contains { $0.id == linkID } == false)
        #expect(model.graph.nodes.count == 7)
        #expect(map.pins.isLinkRemoved("the-pricing-page", "meera"))
        #expect(model.thoughtDetail("meera")?.connections.map(\.thoughtID).contains("the-pricing-page") == false)
    }

    @Test func lookingAtSomethingElseDropsAFixThatWasPartWayThrough() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        model.selection = .thought("running")
        model.pending = .confirmingDelete("running")

        model.selection = .thought("meera")
        #expect(model.pending == nil)

        model.pending = .renaming("meera")
        model.selection = nil
        #expect(model.pending == nil)

        #expect(map.pins.isEmpty)
        #expect(model.graph.nodes.count == 7)
    }

    @Test func aFixThatCannotBeMadeChangesNothing() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        model.selection = .thought("meera")
        model.pending = .renaming("meera")
        let before = model.graph

        // A name that is only spaces, and a thought that is not there.
        await model.perform(.rename(id: "meera", to: "   "))
        await model.perform(.delete(id: "not-a-thought"))

        #expect(model.pending == nil)
        #expect(model.selection == .thought("meera"))
        #expect(model.graph == before)
        #expect(map.pins.isEmpty)
    }

    @Test func aDotKeepsItsPlaceThroughARenameAndTheKeptThoughtStaysPutInAMerge() async throws {
        let map = try await MapFixSandbox()
        let model = map.model
        let before = Dictionary(uniqueKeysWithValues: model.graph.nodes.map { ($0.id, $0.position) })

        await model.perform(.rename(id: "meera", to: "Meera R"))
        await model.perform(.merge(from: "arjun", into: "meera"))

        for node in model.graph.nodes {
            let was = try #require(before[node.id])
            #expect(abs(node.position.x - was.x) <= 0.05)
            #expect(abs(node.position.y - was.y) <= 0.05)
        }
    }
}

/// Pictures of the panel while a fix is being made.
final class MapFixSnapshotTests: XCTestCase {

    private let windowSize = CGSize(width: 1100, height: 600)

    @MainActor
    private func screen(_ model: MapModel, dark: Bool) -> some View {
        MapScreen(
            model: model,
            style: MapStyle(fontName: "Lato-Regular", isLight: !dark),
            onClose: {},
            onOpenEntry: { _ in }
        )
    }

    @MainActor
    private func weekModel(_ change: (inout MemorySnapshot, inout Pins) -> Void = { _, _ in }) throws -> MapModel {
        let model = MapModel(
            store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")),
            applyFix: { _ in false }
        )
        var memory = try MemoryWeek.built().memory
        var pins = Pins()
        change(&memory, &pins)
        model.show(memory: memory)
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        return model
    }

    @MainActor
    private func picture(_ model: MapModel, named name: String, dark: Bool = false) throws {
        attach(try renderOffscreen(screen(model, dark: dark), size: windowSize, dark: dark), named: name)
    }

    @MainActor
    func testTheFixWordsUnderAThought() throws {
        let model = try weekModel()
        model.selection = .thought("saying-yes-under-pressure")
        try picture(model, named: "map-fix-words-light")
        try picture(model, named: "map-fix-words-dark", dark: true)
    }

    @MainActor
    func testRenamingAThought() throws {
        let model = try weekModel()
        model.selection = .thought("trouble-sleeping")
        model.pending = .renaming("trouble-sleeping")
        try picture(model, named: "map-fix-rename")
    }

    @MainActor
    func testPickingTheThoughtToMergeInto() throws {
        let model = try weekModel()
        model.selection = .thought("arjun")
        model.pending = .pickingMergeTarget(source: "arjun")
        try picture(model, named: "map-fix-merge-picking")
    }

    @MainActor
    func testConfirmingAMerge() throws {
        let model = try weekModel()
        model.selection = .thought("arjun")
        model.pending = .confirmingMerge(source: "arjun", target: "meera")
        try picture(model, named: "map-fix-merge-confirm", dark: true)
    }

    @MainActor
    func testGivingAReasonForALink() throws {
        let model = try weekModel()
        model.selection = .thought("running")
        model.pending = .reasonForLink(source: "running", target: "trouble-sleeping")
        try picture(model, named: "map-fix-link-reason")
    }

    @MainActor
    func testConfirmingADelete() throws {
        let model = try weekModel()
        model.selection = .thought("running")
        model.pending = .confirmingDelete("running")
        try picture(model, named: "map-fix-delete-confirm")
    }

    @MainActor
    func testALinkMadeByHandAndRemovingALink() throws {
        let byHand = try weekModel { memory, pins in
            MemoryFixes.apply(.addLink(from: "running", to: "trouble-sleeping", reason: "helps with"), to: &memory, pins: &pins)
        }
        byHand.selection = .link(GraphEdge.id("running", "trouble-sleeping"))
        try picture(byHand, named: "map-fix-link-by-hand")

        let removing = try weekModel()
        let linkID = GraphEdge.id("meera", "the-pricing-page")
        removing.selection = .link(linkID)
        removing.pending = .confirmingRemoveLink(linkID)
        try picture(removing, named: "map-fix-remove-link-confirm")
    }
}
