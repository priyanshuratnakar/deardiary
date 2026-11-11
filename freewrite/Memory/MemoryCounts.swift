//
//  MemoryCounts.swift
//  Dear Diary
//
//  What the app says about memory by counting.
//
//  Before M14 the AI wrote these parts in prose: a description of each
//  thought, notes on how it had shifted, and a profile of the writer. A model
//  asked to reflect adds things that were never written, so now nothing here
//  is written by a model. Each line is a count put into fixed wording:
//  "In 4 entries", "Open since Sunday 8 November 2026". The wording never
//  says "because", "always" or "tends to": two things on the same days are
//  shown as that and nothing more.
//
//  Also here: the names handed to the AI before it reads an entry, so that it
//  uses the name a person, topic or feeling already goes by.
//
//  This file only works on data in hand. It does not read or write files.
//

import Foundation

enum MemoryCounts {
    /// A person or topic needs this many days read in the writer's own words before the
    /// app says how many of them also had an unpleasant feeling. Two days is a coincidence.
    static let daysBeforeFeelingsAreCounted = 3

    // MARK: - Under a thought's name, in the map's panel

    /// The counted lines for a thought.
    /// - Parameter dayLines: the lines kept on each day, by entry. Days read before M14 have none.
    static func lines(for thought: Thought, dayLines: [UUID: [DayLine]]) -> [String] {
        let entries = Set(thought.evidence.map(\.entryID))
        guard !entries.isEmpty, let first = thought.evidence.map(\.date).min(), let last = thought.evidence.map(\.date).max() else {
            return []
        }
        let count = entries.count
        let ownQuotes = Set(thought.evidence.map(\.quote))
        var lines: [String] = []

        /// On how many days one of this thought's own lines is also a line of this kind.
        func days(with kind: DayLine.Kind) -> Int {
            entries.filter { id in
                (dayLines[id] ?? []).contains { $0.kind == kind && ownQuotes.contains($0.quote) }
            }.count
        }

        switch thought.kind {
        case .open:
            lines.append("Open since \(Prompts.longDay(first)).")

        case .helped:
            let helpedOn = max(days(with: .helped), 1)
            lines.append("You wrote that this helped on \(helpedOn) \(helpedOn == 1 ? "day" : "days").")
            if count > helpedOn {
                lines.append(seen(count, first, last))
            }

        case .feeling:
            var tones: [DayLine.Tone: Int] = [:]
            for id in entries {
                for line in dayLines[id] ?? [] where line.kind == .felt && ownQuotes.contains(line.quote) {
                    if let tone = line.tone {
                        tones[tone, default: 0] += 1
                    }
                }
            }
            lines.append("Named on \(count) \(count == 1 ? "day" : "days")\(toneWords(tones, days: count)).")

        default:
            lines.append(seen(count, first, last))
            let helpedOn = days(with: .helped)
            if helpedOn > 0 {
                lines.append("You wrote that this helped on \(helpedOn) \(helpedOn == 1 ? "day" : "days").")
            }
            // Only days read in the writer's own words can be counted.
            let read = entries.filter { dayLines[$0] != nil }
            let unpleasant = read.filter { id in
                (dayLines[id] ?? []).contains { $0.kind == .felt && $0.tone == .unpleasant }
            }.count
            if read.count >= daysBeforeFeelingsAreCounted, unpleasant > 0 {
                let of = read.count == count ? "those \(count) days" : "\(read.count) of those days"
                lines.append("On \(unpleasant) of \(of) you also named an unpleasant feeling.")
            }
        }
        return lines
    }

    private static func seen(_ count: Int, _ first: String, _ last: String) -> String {
        count == 1 || first == last
            ? "In \(count) \(count == 1 ? "entry" : "entries"), on \(Prompts.longDay(first))."
            : "In \(count) entries, from \(span(first, last))."
    }

    /// "Monday 2 November to Thursday 19 November 2026": the year is said once when it is the same.
    static func span(_ first: String, _ last: String) -> String {
        let start = Prompts.longDay(first), end = Prompts.longDay(last)
        let year = " " + String(last.prefix(4))
        if first.prefix(4) == last.prefix(4), start.hasSuffix(year) {
            return "\(start.dropLast(year.count)) to \(end)"
        }
        return "\(start) to \(end)"
    }

    private static func toneWords(_ tones: [DayLine.Tone: Int], days: Int) -> String {
        let order: [DayLine.Tone] = [.unpleasant, .pleasant, .mixed]
        let found = order.filter { (tones[$0] ?? 0) > 0 }
        guard !found.isEmpty else { return "" }
        if found.count == 1, let only = found.first {
            return days == 2 ? ", both \(only.rawValue)" : (days == 1 ? ", \(only.rawValue)" : ", all \(only.rawValue)")
        }
        return ": " + found.map { "\(tones[$0] ?? 0) \($0.rawValue)" }.joined(separator: ", ")
    }

    // MARK: - The profile

    /// The profile: a few counted lines in place of the paragraph the AI used to write.
    /// Talk is given it as background. Empty when there is nothing to count yet.
    /// - Parameter today: the current day, as yyyy-MM-dd.
    static func profile(memory: MemorySnapshot, today: String) -> String {
        var lines: [String] = []
        let recentFrom = MemoryTidier.day(today, minus: 30)

        let lately = memory.thoughts.values
            .filter { $0.kind == .person || $0.kind == .topic }
            .map { thought in (thought, Set(thought.evidence.filter { $0.date >= recentFrom }.map(\.entryID)).count) }
            .filter { $0.1 >= 2 }
            .sorted { ($0.1, $1.0.id) > ($1.1, $0.0.id) }
            .prefix(4)
        if !lately.isEmpty {
            lines.append("Most written about in the last month: " + lately.map { "\($0.0.label) (\($0.1) entries)" }.joined(separator: ", ") + ".")
        }

        let open = memory.thoughts.values.filter { $0.kind == .open }
        if let oldest = open.compactMap(\.firstSeen).min() {
            lines.append(open.count == 1
                ? "Still open: 1 thing, since \(Prompts.longDay(oldest))."
                : "Still open: \(open.count) things, the oldest since \(Prompts.longDay(oldest)).")
        }

        let helped = memory.thoughts.values
            .filter { $0.kind == .helped }
            .sorted { ($0.lastSeen ?? "", $0.id) > ($1.lastSeen ?? "", $1.id) }
            .prefix(3)
        if !helped.isEmpty {
            lines.append("They wrote that these helped: " + helped.map(\.label).joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }
}

/// The names handed to the AI before it reads an entry, so that it uses the name a
/// person, topic or feeling already goes by instead of making a second one.
struct MemoryIndex: Equatable {
    var people: [String] = []
    var topics: [String] = []
    /// Feelings the writer has named before, in their own words.
    var feelings: [String] = []

    /// The most names of each kind that are handed over. The most recently seen come first.
    static let limit = 150
    static let feelingLimit = 60

    init() {}

    init(memory: MemorySnapshot, digests: [EntryDigest]) {
        func recent(_ kinds: Set<ThoughtKind>) -> [String] {
            memory.thoughts.values
                .filter { kinds.contains($0.kind) }
                .sorted { ($0.lastSeen ?? "", $1.id) > ($1.lastSeen ?? "", $0.id) }
                .prefix(Self.limit)
                .map(\.label)
        }
        people = recent([.person])
        // Something that helped is still a thing they may write about again.
        topics = recent([.topic, .helped])

        var seen: Set<String> = []
        let lines = digests
            .filter { !$0.failed }
            .sorted { ($0.entryDate, $0.entryID.uuidString) > ($1.entryDate, $1.entryID.uuidString) }
            .flatMap { $0.lines ?? [] }
        for line in lines where line.kind == .felt {
            guard let word = line.word, let tone = line.tone else { continue }
            let key = FeelingDots.key(word)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            feelings.append("\(word) (\(tone.rawValue))")
            if feelings.count == Self.feelingLimit { break }
        }
    }
}
