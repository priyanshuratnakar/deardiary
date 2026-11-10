//
//  QuoteMatcher.swift
//  Dear Diary
//
//  The check that stops the AI inventing evidence.
//
//  Every quote the AI returns must be found in the entry it cites. Matching
//  forgives two harmless differences: spacing (line breaks, double spaces) and
//  the style of quote marks and dashes (curly or straight). Nothing else: a
//  changed word, a dropped word or "..." means the quote is rejected.
//
//  What is kept is never the AI's version. It is the exact text cut from the entry.
//

import Foundation

enum QuoteMatcher {
    /// Quotes shorter than this are too easy to match by accident.
    static let minimumLength = 8

    /// Finds `quote` in `entry`. Returns the entry's own text for that passage,
    /// or nil if the entry does not contain it.
    static func locate(_ quote: String, in entry: String) -> String? {
        let haystack = normalise(entry)
        guard !haystack.characters.isEmpty else { return nil }

        for candidate in candidates(for: quote) {
            let needle = normalise(candidate).characters
            guard needle.count >= minimumLength, needle.count <= haystack.characters.count else { continue }

            if let start = firstRange(of: needle, in: haystack.characters) {
                let from = haystack.origins[start]
                let lastOrigin = haystack.origins[start + needle.count - 1]
                let to = entry.index(after: lastOrigin)
                let found = String(entry[from..<to]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !found.isEmpty {
                    return found
                }
            }
        }
        return nil
    }

    /// The quote as given, and the quote with one pair of wrapping quote marks removed
    /// (models sometimes wrap what they quote).
    private static func candidates(for quote: String) -> [String] {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = [trimmed]
        let marks: Set<Character> = ["\"", "'", "“", "”", "‘", "’"]
        if trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last, marks.contains(first), marks.contains(last) {
            result.append(String(trimmed.dropFirst().dropLast()))
        }
        return result
    }

    /// Text reduced to what matters for matching, remembering where each character came from.
    private static func normalise(_ text: String) -> (characters: [Character], origins: [String.Index]) {
        var characters: [Character] = []
        var origins: [String.Index] = []
        var pendingSpace: String.Index? = nil

        for index in text.indices {
            let character = text[index]
            if character.isWhitespace || character == "\u{00A0}" {
                if pendingSpace == nil {
                    pendingSpace = index
                }
                continue
            }
            if let spaceIndex = pendingSpace {
                // Runs of spacing become one space, and leading spacing is dropped.
                if !characters.isEmpty {
                    characters.append(" ")
                    origins.append(spaceIndex)
                }
                pendingSpace = nil
            }
            characters.append(canonical(character))
            origins.append(index)
        }
        return (characters, origins)
    }

    /// Curly and straight quote marks are the same; so are the different dashes.
    private static func canonical(_ character: Character) -> Character {
        switch character {
        case "‘", "’", "‚", "‛", "`", "´":
            return "'"
        case "“", "”", "„", "‟":
            return "\""
        case "–", "—", "‒", "―":
            return "-"
        default:
            return character
        }
    }

    private static func firstRange(of needle: [Character], in haystack: [Character]) -> Int? {
        guard let first = needle.first else { return nil }
        let lastStart = haystack.count - needle.count
        var start = 0
        while start <= lastStart {
            if haystack[start] == first, haystack[start..<(start + needle.count)].elementsEqual(needle) {
                return start
            }
            start += 1
        }
        return nil
    }
}
