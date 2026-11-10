//
//  MapSnapshotTests.swift
//  freewriteTests
//
//  Draws the map off screen and attaches the pictures to the test results:
//  the made-up week in light and dark, a thought and a link selected, a crowd
//  of 300 thoughts, and the empty state. Nothing here reads real memory.
//

import XCTest
import SwiftUI
@testable import freewrite

final class MapSnapshotTests: XCTestCase {

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
    private func weekModel() throws -> MapModel {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        model.show(memory: try MemoryWeek.built().memory)
        return model
    }

    @MainActor
    func testTheMadeUpWeekInLightMode() throws {
        let model = try weekModel()
        model.fit(in: windowSize)

        attach(try renderOffscreen(screen(model, dark: false), size: windowSize, dark: false), named: "map-light-week")
        XCTAssertEqual(model.graph.nodes.count, 7)
    }

    @MainActor
    func testAThoughtSelectedInDarkMode() throws {
        let model = try weekModel()
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        model.selection = .thought("saying-yes-under-pressure")

        attach(try renderOffscreen(screen(model, dark: true), size: windowSize, dark: true), named: "map-dark-thought")
    }

    @MainActor
    func testALinkSelectedInLightMode() throws {
        let model = try weekModel()
        model.fit(in: CGSize(width: windowSize.width - 341, height: windowSize.height))
        model.selection = .link(GraphEdge.id("meera", "the-pricing-page"))

        attach(try renderOffscreen(screen(model, dark: false), size: windowSize, dark: false), named: "map-light-link")
    }

    @MainActor
    func testACrowdOfThreeHundredThoughts() throws {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        model.show(memory: MapFixtures.crowd(count: 300))
        model.fit(in: windowSize)

        attach(try renderOffscreen(screen(model, dark: false), size: windowSize, dark: false), named: "map-light-crowd")
        attach(try renderOffscreen(screen(model, dark: true), size: windowSize, dark: true), named: "map-dark-crowd")
        XCTAssertEqual(model.graph.nodes.count, 300)
    }

    @MainActor
    func testAnEmptyMemoryShowsOnePlainMessage() throws {
        let model = MapModel(store: MemoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")))
        model.show(memory: MemorySnapshot())

        attach(try renderOffscreen(screen(model, dark: false), size: windowSize, dark: false), named: "map-light-empty")
        XCTAssertTrue(model.graph.isEmpty)
    }
}
