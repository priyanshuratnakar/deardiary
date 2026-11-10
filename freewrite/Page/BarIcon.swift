//
//  BarIcon.swift
//  Dear Diary
//
//  The small marks in the bottom bar and in History.
//
//  The pictures are in Assets.xcassets/Marks. Names that start with "pika-"
//  are from the free Pikaicons pack (MIT, see PikaIcons-LICENSE.txt beside
//  this file). Names that start with "dd-" were drawn for Dear Diary on the
//  same grid, for the marks the free pack does not have.
//
//  Every mark is drawn in one colour, the colour of the text around it, so it
//  takes freewrite's grey and its hover colour like the words did.
//

import SwiftUI

struct BarIcon: View {
    enum Kind: String, CaseIterable {
        case sidebar = "pika-sidebar"
        case video = "pika-video"
        case chat = "pika-chat"
        case pencil = "pika-pencil"
        case moon = "pika-moon"
        case sun = "pika-sun"
        case trash = "pika-trash"
        case download = "pika-download"
        case clock = "pika-clock"
        case lock = "pika-lock"
        case backspace = "dd-backspace"
        case backspaceOff = "dd-backspace-off"
        case expand = "dd-expand"
        case collapse = "dd-collapse"
        case memory = "dd-memory"
        case arrowUpRight = "dd-arrow-up-right"
    }

    let kind: Kind
    /// The side of the square the mark is drawn in. 16 sits well beside the bar's 13 point words.
    var size: CGFloat = 16

    var body: some View {
        Image(kind.rawValue)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Draws a mark in place of a button's words.
///
/// freewrite's bar buttons are words. Giving one of them this style swaps the word for a
/// mark and leaves the rest of the button (what it does, its hover colour, its pop-up)
/// exactly as freewrite wrote it.
struct BarMark: ButtonStyle {
    let kind: BarIcon.Kind

    init(_ kind: BarIcon.Kind) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        BarIcon(kind: kind)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The name of a mark: shown when the pointer rests on it, and read out by VoiceOver.
    func barName(_ name: String) -> some View {
        help(name).accessibilityLabel(name)
    }
}

/// The mark at the left end of the bar that opens and closes History.
struct HistoryMarkButton: View {
    @Binding var isShowing: Bool
    let textColor: Color
    let textHoverColor: Color
    @Binding var isHoveringBottomNav: Bool

    @State private var isHovering = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowing.toggle()
            }
        }) {
            BarIcon(kind: .sidebar)
        }
        .buttonStyle(.plain)
        .foregroundColor(isHovering || isShowing ? textHoverColor : textColor)
        .barName("History")
        .onHover { hovering in
            isHovering = hovering
            isHoveringBottomNav = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

/// The order the one font mark steps through.
enum FontCycle {
    /// freewrite's four fonts, as it names them in code.
    static let named = ["Lato-Regular", "Arial", ".AppleSystemUIFont", "Times New Roman"]

    /// The font after this one: Lato, Arial, System, Serif, then a surprise from the Mac's
    /// own fonts, then Lato again.
    static func next(after current: String, surprise: () -> String?) -> (font: String, isSurprise: Bool) {
        guard let index = named.firstIndex(of: current) else {
            return (named[0], false)
        }
        if index + 1 < named.count {
            return (named[index + 1], false)
        }
        if let font = surprise() {
            return (font, true)
        }
        return (named[0], false)
    }

    /// The fonts a surprise is picked from: every family on the Mac except the four above.
    static func surprises(from families: [String]) -> [String] {
        let known: Set<String> = ["Lato", "Lato-Regular", "Arial", ".AppleSystemUIFont", "Times New Roman"]
        return families.filter { !known.contains($0) }
    }

    /// What a font is called on screen.
    static func name(of font: String) -> String {
        switch font {
        case "Lato-Regular": return "Lato"
        case ".AppleSystemUIFont": return "System"
        case "Times New Roman": return "Serif"
        default: return font
        }
    }
}

/// One mark for the font, drawn in the font in use. Each click moves to the next one.
struct FontCycleButton: View {
    @Binding var selectedFont: String
    @Binding var currentRandomFont: String
    let availableFonts: [String]
    let textColor: Color
    let textHoverColor: Color
    @Binding var isHoveringBottomNav: Bool

    @State private var isHovering = false

    var body: some View {
        Button(action: {
            let next = FontCycle.next(after: selectedFont) {
                FontCycle.surprises(from: availableFonts).randomElement()
            }
            selectedFont = next.font
            currentRandomFont = next.isSurprise ? next.font : ""
        }) {
            Text("Aa")
                .font(.custom(selectedFont, size: 14))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // A steady box, so a wide or tall font does not push the bar about.
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isHovering ? textHoverColor : textColor)
        .barName("Font: \(FontCycle.name(of: selectedFont))")
        .onHover { hovering in
            isHovering = hovering
            isHoveringBottomNav = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
