//
//  PageSnapshotTests.swift
//  freewriteTests
//
//  Draws the whole writing window off screen and attaches the pictures to the
//  test results: with AI off, with AI on and a (made-up) key saved, with
//  History open on the left, and an empty page with its opening line. Talk is
//  never switched on here, so nothing is sent.
//
//  A picture drawn off screen has no window around it. Where that matters, the
//  strip the real window keeps for its red, yellow and green buttons is added,
//  with three plain circles standing in for the buttons macOS draws.
//

import XCTest
import SwiftUI
@testable import freewrite

final class PageSnapshotTests: XCTestCase {

    private let windowSize = CGSize(width: 1100, height: 600)

    @MainActor
    func testPageWithAIOffLooksLikeFreewrite() throws {
        // Under test the shared settings are a throwaway copy, and AI starts off.
        XCTAssertFalse(AISettings.shared.aiEnabled)

        attach(try renderOffscreen(ContentView(), size: windowSize, dark: false), named: "page-ai-off")
    }

    @MainActor
    func testPageWithAIOnShowsTheTalkWord() throws {
        let settings = AISettings.shared
        settings.aiEnabled = true
        settings.saveAPIKey("made-up-key-for-tests")
        defer {
            settings.aiEnabled = false
            settings.removeAPIKey()
        }

        attach(try renderOffscreen(ContentView(), size: windowSize, dark: false), named: "page-ai-on")
    }

    // MARK: - History on the left, the window buttons, the opening line

    /// The size of the real window: the page, plus the strip for the window buttons.
    private let framedSize = CGSize(width: 1100, height: 632)

    @MainActor
    func testHistoryOpensOnTheLeftBelowTheWindowButtons() throws {
        var page = ContentView()
        page.opensWithHistory = true

        attach(try renderOffscreen(InsideAWindow { page }, size: framedSize, dark: false), named: "page-history-on-the-left")
    }

    @MainActor
    func testAnEmptyPageShowsOneOfTheOpeningLines() throws {
        // An empty entry started just now, in the throwaway journal the tests run on.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let file = StorageRoot.url.appendingPathComponent("[\(UUID().uuidString)]-[\(formatter.string(from: Date()))].md")
        try FileManager.default.createDirectory(at: StorageRoot.url, withIntermediateDirectories: true)
        try "".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        attach(try renderOffscreen(InsideAWindow { ContentView() }, size: framedSize, dark: false), named: "page-empty-with-opening-line")
    }

    @MainActor
    func testEveryMarkInBothModes() throws {
        attach(try renderOffscreen(AllTheMarks(dark: false), dark: false), named: "marks-light")
        attach(try renderOffscreen(AllTheMarks(dark: true), dark: true), named: "marks-dark")
    }
}

/// Stands in for the real window: keeps the top strip clear, as the window does, and draws
/// three plain circles where macOS draws the red, yellow and green buttons.
private struct InsideAWindow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .safeAreaPadding(.top, 32)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 9) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25))
                }
                .frame(width: 60, height: 14)
                .padding(.leading, 9)
                .padding(.top, 9)
            }
    }
}

/// Every mark with its name, in the bar's own grey, at the sizes the app draws them.
private struct AllTheMarks: View {
    let dark: Bool

    private var grey: Color { dark ? Color.gray.opacity(0.8) : Color.gray }
    private var bright: Color { dark ? .white : .black }

    private let rows: [(BarIcon.Kind, String)] = [
        (.sidebar, "History"),
        (.video, "Record a video"),
        (.chat, "Talk or Chat"),
        (.memory, "Memory"),
        (.backspace, "Backspace is On"),
        (.backspaceOff, "Backspace is Off"),
        (.expand, "Fullscreen"),
        (.collapse, "Leave fullscreen"),
        (.pencil, "New Entry"),
        (.moon, "Dark"),
        (.sun, "Light"),
        (.clock, "Earlier versions (History row)"),
        (.download, "Export as PDF (History row)"),
        (.trash, "Delete (History row)"),
        (.arrowUpRight, "Open the folder (History)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.1) { kind, name in
                HStack(spacing: 18) {
                    BarIcon(kind: kind).foregroundColor(grey)
                    BarIcon(kind: kind).foregroundColor(bright)
                    BarIcon(kind: kind, size: 13).foregroundColor(grey)
                    Text(name).font(.system(size: 13)).foregroundColor(grey)
                    Text(kind.rawValue).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 520, alignment: .leading)
        .background(dark ? Color.black : Color.white)
    }
}
