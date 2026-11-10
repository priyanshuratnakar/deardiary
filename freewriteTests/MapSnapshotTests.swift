//
//  MapSnapshotTests.swift
//  freewriteTests
//
//  Draws the map off screen and attaches the pictures to the test results:
//  the made-up week in light and dark, a thought, a link and a day selected,
//  a thought held over another, "Find" in use, a crowd of 300 thoughts with
//  their days, and each empty state. Nothing here reads real memory.
//

import XCTest
import SwiftUI
@testable import freewrite

final class MapSnapshotTests: XCTestCase {

    private let windowSize = CGSize(width: 1100, height: 600)

    @MainActor
    private func screen(_ model: MapModel, dark: Bool, emptyBecause: MapEmptyReason = .waiting) -> some View {
        MapScreen(
            model: model,
            style: MapStyle(fontName: "Lato-Regular", isLight: !dark),
            emptyBecause: emptyBecause,
            onClose: {},
            onOpenEntry: { _ in }
        )
    }

    @MainActor
    private func emptyModel() -> MapModel {
        MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
    }

    @MainActor
    private func weekModel() throws -> MapModel {
        let model = emptyModel()
        let built = try MemoryWeek.built()
        var summaries: [UUID: String] = [:]
        for digest in built.digests {
            summaries[digest.entryID] = digest.summary
        }
        model.show(memory: built.memory, summaries: summaries)
        return model
    }

    @MainActor
    private func picture(_ model: MapModel, named name: String, dark: Bool, emptyBecause: MapEmptyReason = .waiting) throws {
        attach(try renderOffscreen(screen(model, dark: dark, emptyBecause: emptyBecause), size: windowSize, dark: dark), named: name)
    }

    @MainActor
    func testTheMadeUpWeekInLightAndDark() throws {
        let model = try weekModel()
        model.fit(in: windowSize)

        try picture(model, named: "map-light-week", dark: false)
        try picture(model, named: "map-dark-week", dark: true)
        XCTAssertEqual(model.graph.thoughts.count, 7)
        XCTAssertEqual(model.graph.days.count, 4)
    }

    @MainActor
    func testAThoughtSelectedInDarkMode() throws {
        let model = try weekModel()
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        model.selection = .thought("saying-yes-under-pressure")

        try picture(model, named: "map-dark-thought", dark: true)
    }

    @MainActor
    func testALinkSelectedInLightMode() throws {
        let model = try weekModel()
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        model.selection = .link(GraphEdge.id("meera", "the-pricing-page"))

        try picture(model, named: "map-light-link", dark: false)
    }

    @MainActor
    func testADaySelected() throws {
        let model = try weekModel()
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        model.selection = .day(MemoryWeek.monday.id)

        try picture(model, named: "map-light-day", dark: false)
        try picture(model, named: "map-dark-day", dark: true)
        XCTAssertEqual(model.dayDetail(MemoryWeek.monday.id)?.date, "2026-11-02")
    }

    @MainActor
    func testAThoughtHeldOverAnotherSaysWhatLettingGoWillDo() throws {
        let model = try weekModel()
        model.fit(in: windowSize)
        let running = try XCTUnwrap(model.graph.nodes.first { $0.id == "running" })
        let sleep = try XCTUnwrap(model.graph.nodes.first { $0.id == "trouble-sleeping" })
        let from = model.screenPoint(running.position, in: windowSize)
        let to = model.screenPoint(sleep.position, in: windowSize)

        model.drag(from: from, to: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2), in: windowSize, isFirstChange: true)
        model.drag(from: from, to: CGPoint(x: to.x - 6, y: to.y + 5), in: windowSize, isFirstChange: false)

        XCTAssertEqual(model.dropTarget, "trouble-sleeping")
        try picture(model, named: "map-light-dragging-to-link", dark: false)
    }

    @MainActor
    func testFindKeepsTheMatchesBrightAndFadesTheRest() throws {
        let model = try weekModel()
        model.fit(in: windowSize)
        model.isFinding = true
        model.query = "sle"

        XCTAssertEqual(model.matches.map(\.id), ["trouble-sleeping"])
        try picture(model, named: "map-dark-find", dark: true)
    }

    @MainActor
    func testACrowdOfThreeHundredThoughtsWithTheirDays() throws {
        let model = emptyModel()
        model.show(memory: MapFixtures.crowd(count: 300))
        model.fit(in: windowSize)

        try picture(model, named: "map-light-crowd", dark: false)
        try picture(model, named: "map-dark-crowd", dark: true)
        XCTAssertEqual(model.graph.thoughts.count, 300)
        XCTAssertGreaterThan(model.graph.days.count, 200)

        // One of the busiest thoughts, picked out of the crowd.
        let busiest = try XCTUnwrap(model.graph.thoughts.max { ($0.weight, $1.id) < ($1.weight, $0.id) })
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        model.selection = .thought(busiest.id)
        try picture(model, named: "map-dark-crowd-thought", dark: true)
    }

    @MainActor
    func testAJournalKeptForTwoHundredDays() throws {
        let model = emptyModel()
        model.show(memory: MapFixtures.journal(days: 200))
        model.fit(in: windowSize)

        try picture(model, named: "map-dark-journal", dark: true)
        try picture(model, named: "map-light-journal", dark: false)
        XCTAssertGreaterThan(model.graph.days.count, 180)

        // The thought that comes up most, picked out.
        let busiest = try XCTUnwrap(model.graph.thoughts.max { ($0.weight, $1.id) < ($1.weight, $0.id) })
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        model.selection = .thought(busiest.id)
        try picture(model, named: "map-dark-journal-thought", dark: true)
    }

    @MainActor
    func testEachEmptyStateIsOnePlainMessage() throws {
        let model = emptyModel()
        model.show(memory: MemorySnapshot())
        XCTAssertTrue(model.graph.isEmpty)

        try picture(model, named: "map-light-empty", dark: false, emptyBecause: .waiting)
        try picture(model, named: "map-dark-empty-memory-off", dark: true, emptyBecause: .memoryOff)
        try picture(model, named: "map-light-empty-no-ai", dark: false, emptyBecause: .noAI)
    }
}
