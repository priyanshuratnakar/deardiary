//
//  TalkReply.swift
//  Dear Diary
//
//  Turns what a model wrote into what the talk column shows.
//
//  Two things in a reply are the app's to write, not the model's:
//
//  1. A line from an earlier entry. The model points at it by number, like
//     {2}, and the app writes the line out with its day, word for word. A
//     diary must not misquote its writer, and a model asked to retype a line
//     sometimes changes a word.
//  2. The mark a model puts first when someone may be in danger: [care]. It is
//     never shown. It tells the app to show its own help line (see CareNet).
//
//  A cited line is kept in the conversation as a markdown quote:
//
//      > Monday 2 November 2026: "I said yes to everything she asked."
//
//  Only the app writes that. If a model types a line starting with ">" itself,
//  the ">" is taken off, so nothing a model made up can pass as the writer's
//  own earlier words.
//

import Foundation

/// A line from an earlier entry that a reply may point at.
struct EarlierLine: Equatable {
    /// The number the model uses for it, from 1.
    let number: Int
    /// The day the entry was started, as yyyy-MM-dd.
    let date: String
    /// What it was about: the name of the thought it belongs to.
    let label: String
    /// The writer's own words.
    let quote: String

    /// How the line is written into a conversation.
    var asQuoted: String {
        "> \(Prompts.longDay(date)): \"\(quote)\""
    }
}

/// One piece of a message in the talk column.
enum TalkPassage: Equatable {
    case plain(String)
    /// A line from an earlier entry, written out by the app.
    case earlier(day: String, quote: String)

    /// Splits a saved message into its pieces. Paragraphs are separated by a blank line.
    static func split(_ text: String) -> [TalkPassage] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { paragraph in
                guard paragraph.hasPrefix("> ") else { return .plain(paragraph) }
                let body = String(paragraph.dropFirst(2))
                // "Monday 2 November 2026: "the words""
                if let divider = body.range(of: ": \""), body.hasSuffix("\"") {
                    let day = String(body[..<divider.lowerBound])
                    let quote = String(body[divider.upperBound...].dropLast())
                    return .earlier(day: day, quote: quote)
                }
                return .earlier(day: "", quote: body)
            }
    }
}

enum TalkReply {
    static let careTag = "[care]"

    struct Shown: Equatable {
        /// What the column shows, and what is saved.
        var text: String
        /// True if the model marked this reply as one for someone who may be in danger.
        var flaggedCare: Bool
    }

    /// What to show for the model's words so far.
    /// - Parameter finished: false while the reply is still arriving, so that half a mark is not shown.
    static func shown(_ raw: String, lines: [EarlierLine], finished: Bool) -> Shown {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var flaggedCare = false

        // The care mark. It is asked for first, on a line of its own, but counts wherever it is.
        let lowered = text.lowercased()
        if lowered.contains(careTag) {
            flaggedCare = true
            text = text.replacingOccurrences(of: careTag, with: "", options: .caseInsensitive)
        } else if !finished, !lowered.isEmpty, careTag.hasPrefix(lowered) {
            // Only the beginning of the mark has arrived.
            return Shown(text: "", flaggedCare: false)
        }

        // A model may not write an earlier line by itself.
        text = text.components(separatedBy: "\n")
            .map { line -> String in
                var line = line
                while line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    line = String(line.trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return line
            }
            .joined(separator: "\n")

        // The numbers that point at earlier lines. Each line is written out once.
        var used = Set<Int>()
        if let pattern = try? NSRegularExpression(pattern: #"\{\s*(\d{1,2})\s*\}"#) {
            var result = ""
            var cursor = text.startIndex
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 1), in: text) else { continue }
                result += text[cursor..<whole.lowerBound]
                if let number = Int(text[digits]), let line = lines.first(where: { $0.number == number }), !used.contains(number) {
                    used.insert(number)
                    result += "\n\n\(line.asQuoted)\n\n"
                }
                cursor = whole.upperBound
            }
            result += text[cursor...]
            text = result
        }

        // Half a number at the very end, while the reply is still arriving.
        if !finished, let half = text.range(of: #"\{\s*\d{0,2}\s*$"#, options: .regularExpression) {
            text.removeSubrange(half)
        }

        // Tidy the paragraphs: no empty ones, and none that is only a stray full stop.
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { paragraph in
                !paragraph.isEmpty && paragraph.contains(where: { $0.isLetter || $0.isNumber })
            }
        return Shown(text: paragraphs.joined(separator: "\n\n"), flaggedCare: flaggedCare)
    }

    /// True if a reply asks the question the danger rule calls for. A second way of telling
    /// that the model answered with care, in case it left the mark out.
    static func asksIfSafe(_ text: String) -> Bool {
        text.lowercased().contains("are you safe")
    }

    /// True if a reply asks anything.
    static func asksAQuestion(_ text: String) -> Bool {
        TalkPassage.split(text).contains { passage in
            if case .plain(let words) = passage { return words.contains("?") }
            return false
        }
    }

    /// How a question tends to begin when it is typed without a question mark.
    static let questionOpenings = [
        "what", "why", "how", "who", "where", "should", "shall", "could", "would", "does", "did",
        "do you", "do i", "can you", "can i", "is it", "is that", "is this", "are you", "am i",
    ]

    /// True if what the writer typed asks something, with or without a question mark:
    /// "what should i even say to her", "idk. what do you think".
    static func writerAsks(_ text: String) -> Bool {
        if text.contains("?") { return true }
        let sentences = text.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ".!\n"))
            .map { " " + $0.trimmingCharacters(in: .whitespaces) + " " }
        return sentences.contains { sentence in
            questionOpenings.contains { sentence.hasPrefix(" " + $0 + " ") }
        }
    }

    /// A past reply as the model should see it again: an earlier line the app wrote out goes
    /// back to its number if that line is on offer now, and is left out otherwise. The model
    /// never sees a written-out line in its own voice, so it never learns to write one.
    static func forModel(_ text: String, lines: [EarlierLine]) -> String {
        TalkPassage.split(text).compactMap { passage -> String? in
            switch passage {
            case .plain(let words):
                return words
            case .earlier(let day, let quote):
                guard let line = lines.first(where: { $0.quote == quote && Prompts.longDay($0.date) == day }) else { return nil }
                return "{\(line.number)}"
            }
        }
        .joined(separator: "\n\n")
    }
}
