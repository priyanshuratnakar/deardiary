//
//  TalkView.swift
//  Dear Diary
//
//  The quiet conversation column that opens beside the page, and the "Talk"
//  word that sits in the bottom bar.
//
//  It keeps to freewrite's look: no header, no bubbles, no icons. Replies are
//  plain text in the page's own font. Your lines are grey. One input at the bottom.
//
//  Two things in the column are the app's own, not a model's: a line from an
//  earlier entry (grey like your other lines, with its day, beside a thin rule)
//  and the help line shown when someone may be in danger (small, under a rule).
//

import SwiftUI
import AppKit

/// Colours and sizes for the column, taken from the page's current font and theme.
struct TalkStyle: Equatable {
    let fontName: String
    let pageFontSize: CGFloat
    let isLight: Bool

    /// A little smaller than the page, so the page stays the main thing.
    var textSize: CGFloat { max(13, pageFontSize - 4) }
    var quietColor: Color { isLight ? .gray : .gray.opacity(0.8) }
    var strongColor: Color { isLight ? .black : .white }
    var bodyColor: Color {
        isLight ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9)
    }
    var hintColor: Color { isLight ? .gray.opacity(0.5) : .gray.opacity(0.6) }
    /// The thin rules beside an earlier line and above the help line.
    var ruleColor: Color { isLight ? Color(white: 0.88) : Color(white: 0.2) }
    var backgroundColor: Color { isLight ? .white : .black }
}

/// What ContentView places beside the page. It passes the current entry along
/// to the controller and otherwise stays out of the way: typing on the page
/// does not redraw the conversation.
struct TalkView: View {
    let talk: TalkController
    let entryID: UUID?
    let entryFilename: String?
    let entryText: String
    let fontName: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        TalkColumn(
            talk: talk,
            transcript: talk.transcript,
            style: TalkStyle(fontName: fontName, pageFontSize: fontSize, isLight: colorScheme == .light)
        )
        .onAppear {
            talk.show(entry: currentEntry)
        }
        .onChange(of: entryID) { _, _ in
            talk.show(entry: currentEntry)
        }
        .onChange(of: entryText) { _, newText in
            talk.entryTextChanged(newText)
        }
    }

    private var currentEntry: TalkEntry? {
        guard let entryID else { return nil }
        return TalkEntry(id: entryID, text: entryText, date: TalkEntry.date(fromFilename: entryFilename))
    }
}

/// The conversation and the input line.
struct TalkColumn: View {
    let talk: TalkController
    @ObservedObject var transcript: TalkTranscript
    let style: TalkStyle

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private let bottomID = "talk-bottom"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        let order = TalkColumn.drawingOrder(transcript.messages, replyOnItsWay: transcript.isBusy)

                        ForEach(Array(order.settled.enumerated()), id: \.offset) { _, message in
                            messageView(message)
                        }

                        if let reply = transcript.replyInProgress {
                            replyView(reply)
                        }

                        if transcript.isWaiting {
                            line("…", color: style.quietColor)
                        }

                        // The help line stays under the reply it belongs with, while that reply arrives too.
                        if let helpLine = order.underTheReply {
                            messageView(helpLine)
                        }

                        if let notice = transcript.notice {
                            noticeView(notice)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .onAppear {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
                .onChange(of: transcript.messages.count) { _, _ in
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
                .onChange(of: transcript.replyInProgress) { _, _ in
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
                .onChange(of: transcript.isWaiting) { _, _ in
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
                .onChange(of: transcript.notice) { _, _ in
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }

            Divider()

            TextField(
                "Talk",
                text: $draft,
                prompt: Text("Say what's on your mind").foregroundColor(style.hintColor),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.custom(style.fontName, size: style.textSize))
            .foregroundColor(style.bodyColor)
            .lineLimit(1...6)
            .focused($inputFocused)
            .onSubmit(send)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(style.backgroundColor)
        .onChange(of: inputFocused) { _, focused in
            BackspaceLockScope.talkInputFocused = focused
        }
        .onDisappear {
            BackspaceLockScope.talkInputFocused = false
        }
    }

    /// The conversation in the order it is drawn. The app's help line is saved just
    /// before the reply it came with, so it is on the page at once; it is drawn under
    /// that reply. While that reply is still on its way, the line waits below it.
    static func drawingOrder(_ messages: [TalkMessage], replyOnItsWay: Bool) -> (settled: [TalkMessage], underTheReply: TalkMessage?) {
        var settled = messages
        var underTheReply: TalkMessage? = nil
        if replyOnItsWay, let last = settled.last, last.speaker == .note {
            underTheReply = last
            settled.removeLast()
        }
        var index = 0
        while index + 1 < settled.count {
            if settled[index].speaker == .note, settled[index + 1].speaker == .diary {
                settled.swapAt(index, index + 1)
                index += 2
            } else {
                index += 1
            }
        }
        return (settled, underTheReply)
    }

    @ViewBuilder
    private func messageView(_ message: TalkMessage) -> some View {
        switch message.speaker {
        case .you:
            line(message.text, color: style.quietColor)
        case .diary:
            replyView(message.text)
        case .note:
            helpLineView(message.text)
        }
    }

    /// A reply: plain paragraphs, and any line from an earlier entry the app wrote out.
    @ViewBuilder
    private func replyView(_ text: String) -> some View {
        let passages = TalkPassage.split(text)
        if passages.contains(where: { if case .earlier = $0 { return true } else { return false } }) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(passages.enumerated()), id: \.offset) { _, passage in
                    switch passage {
                    case .plain(let words):
                        line(words, color: style.bodyColor)
                    case .earlier(let day, let quote):
                        earlierLineView(day: day, quote: quote)
                    }
                }
            }
        } else {
            line(text, color: style.bodyColor)
        }
    }

    /// The writer's own words from an earlier day: grey, like their other lines.
    private func earlierLineView(day: String, quote: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(style.ruleColor)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 3) {
                if !day.isEmpty {
                    Text(day)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                line("\u{201C}" + quote + "\u{201D}", color: style.quietColor)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// The app's own line about where to reach help.
    private func helpLineView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(style.ruleColor)
                .frame(height: 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(style.bodyColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func line(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.custom(style.fontName, size: style.textSize))
            .foregroundColor(color)
            .lineSpacing(style.textSize * 0.35)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func noticeView(_ notice: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(notice)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if transcript.canRetry {
                TalkWord(title: "Try again", quietColor: style.quietColor, strongColor: style.strongColor) {
                    talk.retry()
                }
            }
        }
    }

    private func send() {
        // Keep what was typed if a reply is still on its way.
        guard !transcript.isBusy else { return }
        let text = draft
        draft = ""
        talk.send(text)
    }
}

/// The "Talk" word in the bottom bar. It takes the place of freewrite's "Chat"
/// when AI is on and a key is saved, and stays dark while talk is on.
struct TalkWordButton: View {
    @ObservedObject var talk: TalkController
    let textColor: Color
    let textHoverColor: Color
    @Binding var isHoveringBottomNav: Bool

    @State private var isHovering = false

    var body: some View {
        Button("Talk") {
            withAnimation(.easeInOut(duration: 0.2)) {
                talk.toggle()
            }
        }
        // A mark in place of the word, brighter while talk is on.
        .buttonStyle(BarMark(.chat))
        .barName("Talk")
        .foregroundColor(isHovering || talk.isOn ? textHoverColor : textColor)
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

/// A small clickable word in the column, in the bottom bar's style.
private struct TalkWord: View {
    let title: String
    let quietColor: Color
    let strongColor: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundColor(isHovering ? strongColor : quietColor)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

/// Decides whether freewrite's "Backspace is Off" lock applies to a key press.
///
/// The lock is about the writing page. It should not stop you fixing a typo in
/// the talk box or in a Settings field, so those are let through.
enum BackspaceLockScope {
    /// Set by the talk column while its input has the keyboard.
    @MainActor static var talkInputFocused = false

    @MainActor
    static func applies(to event: NSEvent) -> Bool {
        if talkInputFocused {
            return false
        }
        // Single-line fields (Settings) are edited through a shared "field editor".
        if let textView = event.window?.firstResponder as? NSTextView, textView.isFieldEditor {
            return false
        }
        return true
    }
}
