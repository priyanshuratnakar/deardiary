//
//  ThoughtNote.swift
//  Dear Diary
//
//  Turns a thought into a markdown note and back again.
//
//  The note is written for people first: it opens in any editor, and in
//  Obsidian the links between notes work because they are [[wikilinks]].
//  A note looks like this:
//
//      ---
//      label: "Saying yes under pressure"
//      kind: theme
//      aliases:
//        - "people-pleasing"
//      first_seen: 2026-11-03
//      last_seen: 2026-11-10
//      ---
//
//      # Saying yes under pressure
//
//      Agreeing in the moment and feeling sick about it afterwards.
//
//      ## Timeline
//
//      - 2026-11-10 · [ENTRY-UUID] · It came up again around the launch call.
//        > I said yes to everything she asked
//
//      ## Evidence
//
//      - 2026-11-10 · [ENTRY-UUID]
//        > I said yes to everything she asked and then felt sick about it
//
//      ## Links
//
//      - [[meera]] · 2026-11-10 · [ENTRY-UUID] · shows up whenever
//        > I keep replaying the call with Meera
//

import Foundation

enum ThoughtNote {
    private static let separator = " · "

    // MARK: - Writing

    static func render(_ thought: Thought) -> String {
        var lines: [String] = ["---"]
        lines.append("label: \(quoted(thought.label))")
        lines.append("kind: \(thought.kind.rawValue)")
        if thought.aliases.isEmpty {
            lines.append("aliases: []")
        } else {
            lines.append("aliases:")
            lines.append(contentsOf: thought.aliases.map { "  - \(quoted($0))" })
        }
        if let firstSeen = thought.firstSeen {
            lines.append("first_seen: \(firstSeen)")
        }
        if let lastSeen = thought.lastSeen {
            lines.append("last_seen: \(lastSeen)")
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(MemoryText.singleLine(thought.label))")
        lines.append("")

        let summary = MemoryText.singleLine(thought.summary)
        if !summary.isEmpty {
            lines.append(summary)
            lines.append("")
        }

        lines.append("## Timeline")
        lines.append("")
        for note in thought.timeline.sorted(by: { ($0.date, $0.note) < ($1.date, $1.note) }) {
            lines.append("- \(note.date)\(separator)[\(note.entryID.uuidString)]\(separator)\(MemoryText.singleLine(note.note))")
            lines.append(contentsOf: quoteLines(note.quote))
        }
        lines.append("")

        lines.append("## Evidence")
        lines.append("")
        for item in thought.evidence.sorted(by: { ($0.date, $0.quote) < ($1.date, $1.quote) }) {
            lines.append("- \(item.date)\(separator)[\(item.entryID.uuidString)]")
            lines.append(contentsOf: quoteLines(item.quote))
        }
        lines.append("")

        lines.append("## Links")
        lines.append("")
        for link in thought.links.sorted(by: { ($0.target, $0.date, $0.reason) < ($1.target, $1.date, $1.reason) }) {
            lines.append("- [[\(link.target)]]\(separator)\(link.date)\(separator)[\(link.entryID.uuidString)]\(separator)\(MemoryText.singleLine(link.reason))")
            lines.append(contentsOf: quoteLines(link.quote))
        }
        lines.append("")

        // Links the user made by hand. They carry a reason but no quote.
        if !thought.userLinks.isEmpty {
            lines.append("## Linked by you")
            lines.append("")
            for link in thought.userLinks.sorted(by: { ($0.target, $0.reason) < ($1.target, $1.reason) }) {
                lines.append("- [[\(link.target)]]\(separator)\(MemoryText.singleLine(link.reason))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// A value written so that any character is safe in the note's header.
    private static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(MemoryText.singleLine(text)),
              let string = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return string
    }

    private static func quoteLines(_ quote: String) -> [String] {
        quote.components(separatedBy: "\n").map { $0.isEmpty ? "  >" : "  > \($0)" }
    }

    // MARK: - Reading

    /// Reads a note back. Returns nil if the text is not recognisably a thought note;
    /// such files are left alone and never overwritten.
    static func parse(_ content: String, id: String) -> Thought? {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let headerEnd = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return nil
        }

        // Header.
        var label: String? = nil
        var kind: ThoughtKind? = nil
        var aliases: [String] = []
        var readingAliases = false
        for line in lines[1..<headerEnd] {
            if readingAliases, line.hasPrefix("  - ") || line.hasPrefix("- ") {
                let value = unquoted(String(line.drop(while: { $0 == " " }).dropFirst(2)))
                if !value.isEmpty { aliases.append(value) }
                continue
            }
            readingAliases = false
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "label":
                label = unquoted(value)
            case "kind":
                kind = ThoughtKind(loose: value)
            case "aliases":
                readingAliases = value.isEmpty
            default:
                break
            }
        }

        // Body.
        var summaryLines: [String] = []
        var section = ""
        var timeline: [TimelineNote] = []
        var evidence: [Evidence] = []
        var links: [ThoughtLink] = []
        var userLinks: [UserLink] = []

        enum Open {
            case none
            case timeline(TimelineNote)
            case evidence(Evidence)
            case link(ThoughtLink)
        }
        var open = Open.none
        var quote: [String] = []

        func close() {
            let text = quote.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            switch open {
            case .timeline(var item):
                item.quote = text
                if !text.isEmpty { timeline.append(item) }
            case .evidence(var item):
                item.quote = text
                if !text.isEmpty { evidence.append(item) }
            case .link(var item):
                item.quote = text
                if !text.isEmpty { links.append(item) }
            case .none:
                break
            }
            open = .none
            quote = []
        }

        for line in lines[(headerEnd + 1)...] {
            if line.hasPrefix("## ") {
                close()
                section = line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                continue
            }
            if line.hasPrefix("# ") {
                if label == nil || label?.isEmpty == true {
                    label = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if section.isEmpty {
                summaryLines.append(line)
                continue
            }

            if line.hasPrefix("- ") {
                close()
                let body = String(line.dropFirst(2))
                switch section {
                case "timeline":
                    let parts = split(body, into: 3)
                    if parts.count == 3, let entryID = entryID(parts[1]) {
                        open = .timeline(TimelineNote(entryID: entryID, date: parts[0], note: parts[2], quote: ""))
                    }
                case "evidence":
                    let parts = split(body, into: 2)
                    if parts.count == 2, let entryID = entryID(parts[1]) {
                        open = .evidence(Evidence(entryID: entryID, date: parts[0], quote: ""))
                    }
                case "links":
                    let parts = split(body, into: 4)
                    if parts.count == 4,
                       parts[0].hasPrefix("[["), parts[0].hasSuffix("]]"),
                       let entryID = entryID(parts[2]) {
                        let target = String(parts[0].dropFirst(2).dropLast(2))
                        open = .link(ThoughtLink(target: target, reason: parts[3], entryID: entryID, date: parts[1], quote: ""))
                    }
                case "linked by you":
                    let parts = split(body, into: 2)
                    if parts.count == 2, parts[0].hasPrefix("[["), parts[0].hasSuffix("]]") {
                        userLinks.append(UserLink(target: String(parts[0].dropFirst(2).dropLast(2)), reason: parts[1]))
                    }
                default:
                    break
                }
            } else if case .none = open {
                continue
            } else {
                let trimmed = line.drop(while: { $0 == " " })
                if trimmed == ">" {
                    quote.append("")
                } else if trimmed.hasPrefix("> ") {
                    quote.append(String(trimmed.dropFirst(2)))
                }
            }
        }
        close()

        guard let label, !label.isEmpty else {
            return nil
        }

        return Thought(
            id: id,
            label: label,
            kind: kind ?? .theme,
            aliases: aliases,
            summary: MemoryText.singleLine(summaryLines.joined(separator: " ")),
            timeline: timeline,
            evidence: evidence,
            links: links,
            userLinks: userLinks
        )
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\""),
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        return trimmed
    }

    /// Splits on " · " into at most `count` parts; the last part keeps any further separators.
    private static func split(_ text: String, into count: Int) -> [String] {
        var parts: [String] = []
        var rest = Substring(text)
        while parts.count < count - 1, let range = rest.range(of: separator) {
            parts.append(rest[..<range.lowerBound].trimmingCharacters(in: .whitespaces))
            rest = rest[range.upperBound...]
        }
        parts.append(rest.trimmingCharacters(in: .whitespaces))
        return parts
    }

    private static func entryID(_ text: String) -> UUID? {
        guard text.hasPrefix("["), text.hasSuffix("]") else { return nil }
        return UUID(uuidString: String(text.dropFirst().dropLast()))
    }
}
