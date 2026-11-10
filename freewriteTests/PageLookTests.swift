//
//  PageLookTests.swift
//  freewriteTests
//
//  Checks the page's own look: the marks in the bar, the one font mark, the
//  opening lines, and the window's red, yellow and green buttons.
//

import AppKit
import Testing
@testable import freewrite

@Suite struct FontCycleTests {

    @Test func eachClickMovesOnAndComesRoundAgain() {
        var font = "Lato-Regular"
        var seen: [String] = []
        for _ in 0..<6 {
            font = FontCycle.next(after: font) { "Noteworthy" }.font
            seen.append(font)
        }

        #expect(seen == ["Arial", ".AppleSystemUIFont", "Times New Roman", "Noteworthy", "Lato-Regular", "Arial"])
    }

    @Test func onlyTheStepAfterSerifIsASurprise() {
        #expect(FontCycle.next(after: "Lato-Regular") { "Noteworthy" }.isSurprise == false)
        #expect(FontCycle.next(after: "Times New Roman") { "Noteworthy" }.isSurprise == true)
        #expect(FontCycle.next(after: "Noteworthy") { "Papyrus" } == ("Lato-Regular", false))
    }

    @Test func aMacWithNoOtherFontsGoesStraightBackToLato() {
        #expect(FontCycle.next(after: "Times New Roman") { nil } == ("Lato-Regular", false))
    }

    @Test func aSurpriseIsNeverOneOfTheFourNamedFonts() {
        let families = ["Arial", "Noteworthy", "Lato", "Times New Roman", "Papyrus"]

        #expect(FontCycle.surprises(from: families) == ["Noteworthy", "Papyrus"])
    }

    @Test func fontsAreCalledWhatFreewriteCalledThem() {
        #expect(FontCycle.named.map(FontCycle.name(of:)) == ["Lato", "Arial", "System", "Serif"])
        #expect(FontCycle.name(of: "Noteworthy") == "Noteworthy")
    }
}

@Suite struct OpeningLineTests {

    @Test func theOpeningLinesAreDearDiarysOwn() {
        let lines = OpeningLines.all

        #expect(lines.count >= 6)
        #expect(Set(lines).count == lines.count)
        #expect(lines.contains("what's up, bbg"))
        #expect(!lines.contains("Begin writing"))
        // Each fits on one line of the page at any text size.
        #expect(lines.allSatisfy { !$0.isEmpty && $0.count <= 32 && !$0.contains("\n") })
    }
}

@Suite @MainActor struct BarIconTests {

    @Test func everyMarkHasItsPictureAndTakesTheColourOfTheTextAroundIt() throws {
        for kind in BarIcon.Kind.allCases {
            let image = try #require(NSImage(named: kind.rawValue), "No picture for \(kind.rawValue)")
            #expect(image.isTemplate, "\(kind.rawValue) should be drawn in one colour")
            #expect(image.size == NSSize(width: 24, height: 24), "\(kind.rawValue) should be on the 24 point grid")
        }
    }

    @Test func pikasMarksAndDearDiarysOwnAreToldApartByName() {
        let names = BarIcon.Kind.allCases.map(\.rawValue)

        #expect(names.allSatisfy { $0.hasPrefix("pika-") || $0.hasPrefix("dd-") })
        #expect(names.filter { $0.hasPrefix("pika-") }.count == 9)
        #expect(Set(names).count == names.count)
    }

    @Test func pikasLicenceTravelsWithTheApp() throws {
        let url = try #require(Bundle.main.url(forResource: "PikaIcons-LICENSE", withExtension: "txt"))
        let notice = try String(contentsOf: url, encoding: .utf8)

        #expect(notice.contains("MIT License"))
        #expect(notice.contains("Copyright (c) 2026 Pikaicons"))
        #expect(notice.contains("The above copyright notice and this permission notice shall be included"))
    }
}

@Suite(.serialized) @MainActor struct WindowButtonTests {

    @Test func theButtonsShowUnlessThePageHasGoneQuiet() {
        #expect(WindowButtons.shouldShow(isQuiet: false, pointerIsOverStrip: false, isFullscreen: false))
        #expect(!WindowButtons.shouldShow(isQuiet: true, pointerIsOverStrip: false, isFullscreen: false))
        // The pointer going to the top of the window brings them back.
        #expect(WindowButtons.shouldShow(isQuiet: true, pointerIsOverStrip: true, isFullscreen: false))
        // In fullscreen macOS looks after them.
        #expect(WindowButtons.shouldShow(isQuiet: true, pointerIsOverStrip: false, isFullscreen: true))
    }

    /// True if a view can be seen: neither it nor anything it sits in is hidden or fully faded.
    private func canBeSeen(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let step = current {
            if step.isHidden || step.alphaValue < 0.99 { return false }
            current = step.superview
        }
        return true
    }

    private func wait(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @Test func theJournalWindowShowsItsRedYellowAndGreenButtons() async throws {
        // The tests run inside the app itself, so its real window is here.
        await wait(0.5)
        let buttons = WindowButtons.shared.buttons
        try #require(buttons.count == 3, "The journal window was not found")

        #expect(buttons.allSatisfy(canBeSeen))
        // Top left, in the strip the page leaves clear.
        let window = try #require(buttons[0].window)
        for button in buttons {
            let frame = button.convert(button.bounds, to: nil)
            #expect(frame.minX < 80)
            #expect(window.frame.height - frame.maxY < 32)
        }
    }

    @Test func theyStepBackWithTheBarAndComeBackWithIt() async throws {
        await wait(0.5)
        let buttons = WindowButtons.shared.buttons
        try #require(buttons.count == 3, "The journal window was not found")

        WindowButtons.shared.setQuiet(true)
        await wait(1.4)
        #expect(buttons.allSatisfy { $0.isHidden })

        WindowButtons.shared.setQuiet(false)
        await wait(0.5)
        #expect(buttons.allSatisfy(canBeSeen))
    }
}
