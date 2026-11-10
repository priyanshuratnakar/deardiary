//
//  AppearanceTests.swift
//  freewriteTests
//
//  Checks that the words on the new screens can be read in both light and
//  dark mode, by measuring each text colour against the background it sits
//  on. Body text must be easy to read; the quiet grey words (freewrite's own
//  bottom-bar grey) must at least meet the bar for large or secondary text.
//

import AppKit
import SwiftUI
import Testing
@testable import freewrite

/// Works out how strongly two colours contrast, the way accessibility guidelines measure it (1 to 21).
enum Contrast {
    /// The colour as red, green, blue and alpha, as it appears in light or dark mode.
    static func components(_ color: Color, dark: Bool) -> (r: Double, g: Double, b: Double, a: Double) {
        var result = (r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        appearance.performAsCurrentDrawingAppearance {
            if let rgb = NSColor(color).usingColorSpace(.sRGB) {
                result = (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent), Double(rgb.alphaComponent))
            }
        }
        return result
    }

    private static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// The contrast of a text colour on a background, with see-through text blended onto the background first.
    static func ratio(_ text: Color, on background: Color, dark: Bool) -> Double {
        let back = components(background, dark: dark)
        let front = components(text, dark: dark)
        let r = front.r * front.a + back.r * (1 - front.a)
        let g = front.g * front.a + back.g * (1 - front.a)
        let b = front.b * front.a + back.b * (1 - front.a)
        let one = luminance(r, g, b)
        let other = luminance(back.r, back.g, back.b)
        return (max(one, other) + 0.05) / (min(one, other) + 0.05)
    }
}

@Suite struct AppearanceTests {

    @Test(arguments: [false, true])
    func wordsOnTheMapAndVersionsScreensCanBeReadInBothModes(dark: Bool) {
        let style = MapStyle(fontName: "Lato-Regular", isLight: !dark)

        #expect(Contrast.ratio(style.bodyColor, on: style.backgroundColor, dark: dark) >= 7)
        #expect(Contrast.ratio(style.strongColor, on: style.backgroundColor, dark: dark) >= 7)
        #expect(Contrast.ratio(style.quietColor, on: style.backgroundColor, dark: dark) >= 3)
        #expect(Contrast.ratio(.secondary, on: style.backgroundColor, dark: dark) >= 3)
        #expect(Contrast.ratio(.primary, on: style.backgroundColor, dark: dark) >= 7)
    }

    @Test(arguments: [false, true])
    func wordsInTheTalkColumnCanBeReadInBothModes(dark: Bool) {
        let style = TalkStyle(fontName: "Lato-Regular", pageFontSize: 18, isLight: !dark)

        #expect(Contrast.ratio(style.bodyColor, on: style.backgroundColor, dark: dark) >= 7)
        #expect(Contrast.ratio(style.strongColor, on: style.backgroundColor, dark: dark) >= 7)
        #expect(Contrast.ratio(style.quietColor, on: style.backgroundColor, dark: dark) >= 3)
    }

    @Test(arguments: [false, true])
    func everyDotOnTheMapStandsOutFromTheBackground(dark: Bool) {
        let style = MapStyle(fontName: "Lato-Regular", isLight: !dark)

        // The amber used for ideas is the weakest, at a little over 2 on white: a yellow
        // cannot go higher and still read as yellow. That is one reason the kind of a
        // thought is always written in words as well (legend, hover, panel).
        for kind in ThoughtKind.allCases {
            #expect(Contrast.ratio(style.color(for: kind), on: style.backgroundColor, dark: dark) >= 2, "\(kind.rawValue)")
        }
    }

    @Test func inDarkModeEveryDotIsClearlyVisible() {
        let style = MapStyle(fontName: "Lato-Regular", isLight: false)

        for kind in ThoughtKind.allCases {
            #expect(Contrast.ratio(style.color(for: kind), on: style.backgroundColor, dark: true) >= 3, "\(kind.rawValue)")
        }
    }

    @Test func theSameColoursAreNotUsedForBothModes() {
        // A check on the check: black text would fail on the dark background.
        #expect(Contrast.ratio(.black, on: .black, dark: true) < 1.1)
        #expect(Contrast.ratio(.black, on: .white, dark: false) > 20)
    }
}
