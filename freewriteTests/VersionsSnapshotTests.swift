//
//  VersionsSnapshotTests.swift
//  freewriteTests
//
//  Draws the versions screen off screen and attaches the pictures to the test
//  results: an earlier version chosen, the version that matches the entry
//  chosen, and an entry with no versions. Nothing here reads a real journal.
//

import XCTest
import SwiftUI
@testable import freewrite

final class VersionsSnapshotTests: XCTestCase {

    private let windowSize = CGSize(width: 1100, height: 600)

    private static let drafts: [(text: String, day: Int, hour: Int, minute: Int)] = [
        (MemoryWeek.monday.text, 9, 21, 15),
        (MemoryWeek.monday.text.components(separatedBy: "\n").prefix(3).joined(separator: "\n") + "\n\nMaybe I should just tell her tomorrow.", 9, 21, 10),
        (MemoryWeek.monday.text.components(separatedBy: "\n").prefix(2).joined(separator: "\n"), 2, 23, 20),
        (MemoryWeek.monday.text.components(separatedBy: "\n").prefix(1).joined(separator: "\n"), 2, 23, 5),
    ]

    @MainActor
    private func model(rows: Bool = true, selecting index: Int? = nil) -> VersionsModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-unused-\(UUID().uuidString)")
        let model = VersionsModel(
            entryID: MemoryWeek.monday.id,
            store: SnapshotStore(root: root),
            journal: JournalReader(root: root, welcomeText: nil),
            keep: { _, _ in false }
        )
        let made = Self.drafts.enumerated().map { index, draft in
            VersionRow(
                version: EntryVersion(
                    entryID: MemoryWeek.monday.id,
                    savedAt: MemoryWeek.day(draft.day, hour: draft.hour, minute: draft.minute),
                    url: URL(fileURLWithPath: "/made-up/[\(index)].md")
                ),
                text: draft.text,
                words: VersionText.words(draft.text),
                isCurrent: index == 0
            )
        }
        model.show(rows: rows ? made : [], entryStartedAt: MemoryWeek.monday.startedAt, selecting: index.map { made[$0].id })
        return model
    }

    @MainActor
    private func screen(_ model: VersionsModel, dark: Bool) -> some View {
        VersionsScreen(
            model: model,
            style: MapStyle(fontName: "Lato-Regular", isLight: !dark),
            fontSize: 18,
            onRestore: {},
            onClose: {}
        )
    }

    @MainActor
    func testAnEarlierVersionInLightAndDark() throws {
        let model = model()
        XCTAssertEqual(model.selected?.isCurrent, false)

        attach(try renderOffscreen(screen(model, dark: false), size: windowSize, dark: false), named: "versions-light")
        attach(try renderOffscreen(screen(model, dark: true), size: windowSize, dark: true), named: "versions-dark")
    }

    @MainActor
    func testTheVersionThatMatchesTheEntryOffersNoRestore() throws {
        let model = model(selecting: 0)
        XCTAssertEqual(model.selected?.isCurrent, true)

        attach(try renderOffscreen(screen(model, dark: false), size: windowSize, dark: false), named: "versions-light-current")
    }

    @MainActor
    func testAnEntryWithNoVersionsShowsOnePlainMessage() throws {
        let model = model(rows: false)
        XCTAssertTrue(model.rows.isEmpty)

        attach(try renderOffscreen(screen(model, dark: false), size: windowSize, dark: false), named: "versions-light-empty")
        attach(try renderOffscreen(screen(model, dark: true), size: windowSize, dark: true), named: "versions-dark-empty")
    }

    @MainActor
    func testTheHistoryIconShowsOnlyForEntriesWithAnEarlierVersion() throws {
        let index = VersionIndex()
        index.entries = [MemoryWeek.monday.id]
        let row = HStack(spacing: 8) {
            VersionsIconButton(entryID: MemoryWeek.monday.id, isLight: true, index: index) {}
            VersionsIconButton(entryID: MemoryWeek.friday.id, isLight: true, index: index) {}
        }
        .padding(8)
        .background(Color.white)

        // One icon is drawn, not two: Friday's entry has no earlier version.
        let image = try renderOffscreen(row, dark: false)
        attach(image, named: "versions-history-icon")
        XCTAssertLessThan(image.size.width, 40)
    }
}
