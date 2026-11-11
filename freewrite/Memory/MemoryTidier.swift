//
//  MemoryTidier.swift
//  Dear Diary
//
//  Decides what from the weekly tidy is allowed to change memory.
//
//  Entries are read one at a time, so the same person or topic can end up
//  under two names, and things mentioned once pile up. The tidy looks across
//  all of memory for those two things. Nothing is taken on trust:
//
//  - A merge needs both thoughts to exist, never folds away a thought the
//    user renamed or linked by hand, never joins a person with something
//    that is not a person, and leaves feelings and open things alone.
//  - "Retire" is only a suggestion. The app's own rule decides: the thought
//    is a person or a topic, it appears in exactly one entry, that entry is
//    more than three weeks old, and the user has not renamed or linked it.
//    A retired thought can come back if it returns.
//  - The user's fixes have the last word, as always.
//
//  Until M14 the tidy also named "patterns across weeks" and rewrote a
//  profile. What recurs is now counted by the app (MemoryCounts), so the
//  AI is no longer asked to say it.
//
//  This file only works on data in hand. It does not read or write files.
//

import Foundation

enum MemoryTidier {
    struct Rules {
        /// A thought seen in one entry can be retired once that entry is this many days old.
        var oneOffAfterDays = 21
    }

    struct Outcome: Equatable {
        var merged = 0
        var retired = 0
        /// What was refused, and why.
        var rejected: [EntryDigest.Rejection] = []

        /// What the tidy did, in a few plain words.
        var line: String {
            var parts: [String] = []
            if merged > 0 { parts.append("merged \(merged)") }
            if retired > 0 { parts.append("retired \(retired)") }
            return parts.isEmpty ? "nothing needed changing" : parts.joined(separator: ", ")
        }
    }

    /// Kinds the tidy never folds away or retires: they are the writer's own words for
    /// something, or something that stays until the writer closes it.
    private static let leftAlone: Set<ThoughtKind> = [.feeling, .open]
    /// Kinds that are never retired for being seen once: one mention is the whole point.
    private static let keptWhenSeenOnce: Set<ThoughtKind> = [.feeling, .open, .helped]

    /// - Parameter today: the current day, as yyyy-MM-dd.
    static func apply(_ result: TidyResult, to memory: inout MemorySnapshot, pins: Pins, today: String, rules: Rules = Rules()) -> Outcome {
        var outcome = Outcome()
        /// Thoughts folded away in this tidy, and where they went.
        var folded: [String: String] = [:]

        func reject(_ item: String, _ reason: String) {
            outcome.rejected.append(EntryDigest.Rejection(item: item, reason: reason))
        }

        func current(_ reference: String) -> String {
            var id = pins.resolve(reference.trimmingCharacters(in: .whitespacesAndNewlines))
            var steps = 0
            while let next = folded[id], steps < 20 {
                id = pins.resolve(next)
                steps += 1
            }
            return id
        }

        // 1. Duplicates.
        for merge in result.merges {
            let from = current(merge.from)
            let into = current(merge.into)
            guard let source = memory.thoughts[from], let target = memory.thoughts[into] else {
                reject("merge", "It named a thought that is not in memory.")
                continue
            }
            guard from != into else {
                reject("merge", "It merged a thought into itself.")
                continue
            }
            guard !pins.isTouchedByUser(from) else {
                reject("merge", "You renamed or linked this thought.")
                continue
            }
            guard !leftAlone.contains(source.kind), !leftAlone.contains(target.kind) else {
                reject("merge", "Feelings and open things are left as you wrote them.")
                continue
            }
            guard (source.kind == .person) == (target.kind == .person) else {
                reject("merge", "A person is not folded into something that is not a person.")
                continue
            }
            MemoryFixes.fold(from, into: into, in: &memory)
            folded[from] = into
            outcome.merged += 1
        }

        // 2. One-offs. The model suggests; this rule decides.
        let cutoff = day(today, minus: rules.oneOffAfterDays)
        for reference in result.retire {
            let id = current(reference)
            guard let thought = memory.thoughts[id] else {
                reject("retire", "It named a thought that is not in memory.")
                continue
            }
            guard !pins.isTouchedByUser(id) else {
                reject("retire", "You renamed or linked this thought.")
                continue
            }
            guard !keptWhenSeenOnce.contains(thought.kind) else {
                reject("retire", "It is kept even when seen once.")
                continue
            }
            let entries = Set(thought.evidence.map(\.entryID))
            guard entries.count == 1, let lastSeen = thought.lastSeen, lastSeen <= cutoff else {
                reject("retire", "It is not a one-off.")
                continue
            }
            memory.thoughts[id] = nil
            for other in memory.thoughts.keys {
                memory.thoughts[other]?.links.removeAll { $0.target == id }
            }
            outcome.retired += 1
        }

        // 3. The user's fixes have the last word.
        MemoryFixes.enforce(pins, on: &memory)
        return outcome
    }

    /// A day some days earlier, as yyyy-MM-dd.
    static func day(_ day: String, minus days: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day),
              let earlier = Calendar.current.date(byAdding: .day, value: -days, to: date) else {
            return day
        }
        return formatter.string(from: earlier)
    }
}
