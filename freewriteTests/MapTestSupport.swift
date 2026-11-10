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

    /// A memory with `count` thoughts, each seen in one or more made-up entries, and roughly
    /// one and a half links per thought. A few thoughts recur much more than the rest.
    static func crowd(count: Int, seed: UInt64 = 7) -> MemorySnapshot {
        var numbers = Numbers(seed: seed)
        var memory = MemorySnapshot()
        let kinds = ThoughtKind.allCases
        let ids = (0..<count).map { "thought-\($0)" }

        for (index, id) in ids.enumerated() {
            let recurrences = index % 17 == 0 ? 6 + numbers.next(below: 20) : 1 + numbers.next(below: 4)
            let evidence = (0..<recurrences).map { occurrence in
                Evidence(
                    entryID: UUID(uuidString: String(format: "00000000-0000-0000-%04d-%012d", index % 10_000, occurrence))!,
                    date: String(format: "2026-%02d-%02d", 1 + (index + occurrence) % 12, 1 + (index * 3 + occurrence) % 28),
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
