//
//  MapTestSupport.swift
//  freewriteTests
//
//  Made-up memory for the map tests: a crowd of thoughts with links between
//  them, built the same way every time so pictures and timings can be compared.
//

import Foundation
@testable import freewrite

enum MapFixtures {
    /// A simple, repeatable source of numbers. The same seed always gives the same sequence.
    struct Numbers {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next(below limit: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(max(limit, 1)))
        }
    }

    private static let words = [
        "work", "sleep", "running", "money", "home", "mother", "writing", "friends", "the move", "deadline",
        "doubt", "quiet", "anger", "plans", "weekends", "reading", "health", "the team", "travel", "habits",
    ]

    /// A memory shaped like a real journal kept for `days` days: a dozen thoughts that keep
    /// coming back, some that return now and then, and many that were mentioned once.
    static func journal(days: Int = 200, seed: UInt64 = 21) -> MemorySnapshot {
        var numbers = Numbers(seed: seed)
        var memory = MemorySnapshot()
        // Mostly topics and people, as a journal read in the shape memory has had since M14:
        // few things help or stay open, and a feeling is only a dot once it has been named twice.
        let kinds: [ThoughtKind] = [.topic, .topic, .topic, .topic, .person, .person, .person, .open, .helped, .topic]
        let recurring: [(String, ThoughtKind, Int)] = [
            ("Meera", .person, 42), ("work", .topic, 34), ("couldn't sleep", .feeling, 30),
            ("Ma", .person, 26), ("money", .topic, 22), ("the launch", .topic, 18), ("a run before work", .helped, 16),
            ("tired", .feeling, 14), ("the novel", .topic, 12), ("Arjun", .person, 10),
            ("the move", .topic, 9), ("Tanvi", .person, 8),
        ]
        func entry(_ day: Int) -> (UUID, String) {
            (UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", day))!,
             String(format: "2026-%02d-%02d", 1 + (day / 28) % 12, 1 + day % 28))
        }
        func add(_ id: String, label: String, kind: ThoughtKind, day: Int) {
            let (entryID, date) = entry(day)
            var thought = memory.thoughts[id] ?? Thought(id: id, label: label, kind: kind)
            if !thought.evidence.contains(where: { $0.entryID == entryID }) {
                thought.evidence.append(Evidence(entryID: entryID, date: date, quote: "A made-up line about \(label.lowercased())."))
            }
            memory.thoughts[id] = thought
        }

        for day in 0..<days {
            // Out of a hundred days, each recurring thought comes up on about this many.
            for (index, item) in recurring.enumerated() where numbers.next(below: 100) < item.2 {
                add("recurring-\(index)", label: item.0, kind: item.1, day: day)
            }
            // Most days also mention something once and never again.
            if numbers.next(below: 100) < 60 {
                add("once-\(day)", label: "Once \(day)", kind: kinds[numbers.next(below: kinds.count)], day: day)
            }
        }
        // Thoughts that return a few times.
        for index in 0..<(days / 4) {
            let kind = kinds[numbers.next(below: kinds.count)]
            for _ in 0..<(2 + numbers.next(below: 4)) {
                add("sometimes-\(index)", label: "Sometimes \(index)", kind: kind, day: numbers.next(below: days))
            }
        }
        // A few links between the thoughts that keep coming back.
        for (from, to) in [(0, 1), (2, 0), (1, 7), (3, 4), (5, 2), (6, 2), (8, 3), (9, 0), (10, 4), (11, 3)] {
            guard let first = memory.thoughts["recurring-\(from)"]?.evidence.first, memory.thoughts["recurring-\(to)"] != nil else { continue }
            memory.thoughts["recurring-\(from)"]?.links.append(ThoughtLink(target: "recurring-\(to)", reason: MemoryApplier.sameSentence, entryID: first.entryID, date: first.date, quote: first.quote))
        }
        return memory
    }

    /// A memory with `count` thoughts, each seen in one or more made-up entries, and roughly
    /// one and a half links per thought. A few thoughts recur much more than the rest.
    static func crowd(count: Int, seed: UInt64 = 7) -> MemorySnapshot {
        var numbers = Numbers(seed: seed)
        var memory = MemorySnapshot()
        let kinds = ThoughtKind.journal
        let ids = (0..<count).map { "thought-\($0)" }

        for (index, id) in ids.enumerated() {
            let recurrences = index % 17 == 0 ? 6 + numbers.next(below: 20) : 1 + numbers.next(below: 4)
            let evidence = (0..<recurrences).map { occurrence -> Evidence in
                // About 240 days in all, shared between thoughts as they would be in a real journal.
                let day = (index * 7 + occurrence * 13) % 240
                return Evidence(
                    entryID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", day))!,
                    date: String(format: "2026-%02d-%02d", 1 + day % 12, 1 + (day / 12) % 28),
                    quote: "A made-up line about \(words[index % words.count]), number \(occurrence)."
                )
            }
            memory.thoughts[id] = Thought(
                id: id,
                label: "\(words[index % words.count].capitalized) \(index)",
                kind: kinds[numbers.next(below: kinds.count)],
                summary: "A made-up thought for testing the map.",
                evidence: evidence
            )
        }

        for (index, id) in ids.enumerated() where count > 1 {
            let linkCount = numbers.next(below: 3)
            for _ in 0..<linkCount {
                // Mostly to nearby thoughts, so the map has clusters, with the odd long link.
                let nearby = numbers.next(below: 10) < 8
                let other = nearby ? (index + 1 + numbers.next(below: 6)) % count : numbers.next(below: count)
                guard other != index, let first = memory.thoughts[id]?.evidence.first else { continue }
                memory.thoughts[id]?.links.append(ThoughtLink(
                    target: ids[other],
                    reason: "shows up with",
                    entryID: first.entryID,
                    date: first.date,
                    quote: first.quote
                ))
            }
        }
        return memory
    }
}
