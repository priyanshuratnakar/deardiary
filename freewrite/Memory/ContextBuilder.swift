//
//  ContextBuilder.swift
//  Dear Diary
//
//  Picks which parts of memory go along with a talk message.
//
//  This runs on the Mac with no AI call. It sends the profile, the thoughts
//  whose names appear in the open entry or in what was just said, the thoughts
//  that entry was already found to touch, and the thoughts linked to those,
//  each with a few dated lines quoted from earlier entries.
//
//  Lines from the open entry are left out: talk already has the entry itself.
//  There is no search index; names and links are enough to start with.
//

import Foundation

/// The slice of memory sent with one talk message.
struct TalkMemoryContext: Equatable {
    /// A line quoted from an earlier entry.
    struct Quote: Equatable {
        /// The day the entry was started, as yyyy-MM-dd.
        let date: String
        let text: String
    }

    /// A note on how a thought shifted.
    struct Shift: Equatable {
        let date: String
        let note: String
    }

    /// A connection to another thought that is also being sent.
    struct Connection: Equatable {
        let label: String
        let reason: String
        let date: String
        let quote: String
    }

    struct Item: Equatable {
        let id: String
        let label: String
        let kind: ThoughtKind
        let summary: String
        /// Oldest first.
        let quotes: [Quote]
        let shifts: [Shift]
        let connections: [Connection]
    }

    /// What an entry behind one of the quotes was about.
    struct DaySummary: Equatable {
        let date: String
        let summary: String
    }

    var profile: String = ""
    var thoughts: [Item] = []
    var days: [DaySummary] = []

    var isEmpty: Bool {
        profile.isEmpty && thoughts.isEmpty
    }
}

enum ContextBuilder {
    struct Limits {
        /// Thoughts named in the entry or the conversation.
        var named = 6
        /// Thoughts linked to those.
        var neighbours = 6
        var quotesPerThought = 3
        var shiftsPerThought = 2
        var daySummaries = 6
        /// A ceiling on the size of everything picked, so a message stays small.
        var maxCharacters = 9_000
    }

    /// Picks the context for a reply.
    /// - Parameters:
    ///   - entry: the entry open on the page.
    ///   - recentMessages: the last few things the user said in the column, oldest first.
    static func build(
        entry: TalkEntry,
        recentMessages: [String],
        memory: MemorySnapshot,
        digests: [EntryDigest],
        limits: Limits = Limits()
    ) -> TalkMemoryContext {
        var context = TalkMemoryContext(profile: memory.profile.trimmingCharacters(in: .whitespacesAndNewlines))

        // Only thoughts with something from before this entry are worth sending.
        let candidates = memory.thoughts.values.filter { thought in
            thought.evidence.contains { $0.entryID != entry.id }
        }
        guard !candidates.isEmpty else {
            return context
        }

        // 1. Score each thought by where its name turns up.
        let entryWords = padded(entry.text)
        let messageWords = padded(recentMessages.joined(separator: "\n"))
        let touchedByEntry = Set(digests.first { $0.entryID == entry.id && !$0.failed }?.thoughts ?? [])

        var scores: [String: Int] = [:]
        for thought in candidates {
            let names = searchNames(for: thought)
            var score = 0
            if names.contains(where: { messageWords.contains($0) }) {
                score += 3
            }
            if names.contains(where: { entryWords.contains($0) }) {
                score += 2
            }
            if touchedByEntry.contains(thought.id) {
                score += 2
            }
            if score > 0 {
                scores[thought.id] = score
            }
        }

        let named = candidates
            .filter { scores[$0.id] != nil }
            .sorted { first, second in
                let left = (scores[first.id] ?? 0, first.lastSeen ?? "", first.evidence.count)
                let right = (scores[second.id] ?? 0, second.lastSeen ?? "", second.evidence.count)
                return left != right ? left > right : first.id < second.id
            }
            .prefix(limits.named)
        let namedIDs = Set(named.map(\.id))

        // 2. Their linked neighbours, one step away in either direction.
        var neighbourIDs: Set<String> = []
        for thought in candidates {
            for link in thought.links where link.entryID != entry.id {
                if namedIDs.contains(thought.id), !namedIDs.contains(link.target) {
                    neighbourIDs.insert(link.target)
                }
                if namedIDs.contains(link.target), !namedIDs.contains(thought.id) {
                    neighbourIDs.insert(thought.id)
                }
            }
        }
        let neighbours = candidates
            .filter { neighbourIDs.contains($0.id) }
            .sorted { ($0.lastSeen ?? "", $0.id) > ($1.lastSeen ?? "", $1.id) }
            .prefix(limits.neighbours)

        // 3. Build what is sent, dropping the least relevant until it fits.
        // Neighbours go first, then the day summaries, and the named thoughts last.
        var chosen = Array(named) + Array(neighbours)
        var includeDays = true
        while true {
            let included = Set(chosen.map(\.id))
            let labels = Dictionary(uniqueKeysWithValues: chosen.map { ($0.id, $0.label) })
            context.thoughts = chosen.map { item(for: $0, openEntry: entry.id, included: included, labels: labels, limits: limits) }
            context.days = includeDays
                ? daySummaries(for: context.thoughts, chosen: chosen, openEntry: entry.id, digests: digests, limits: limits)
                : []
            if size(of: context) <= limits.maxCharacters || chosen.isEmpty {
                break
            }
            if chosen.count > 1 {
                chosen.removeLast()
            } else if includeDays {
                includeDays = false
            } else {
                chosen.removeLast()
            }
        }
        return context
    }

    // MARK: - Names

    /// The text as lower-case words with a space at each end, so a name can be
    /// looked for as whole words: " meera " is found in " i saw meera today ".
    private static func padded(_ text: String) -> String {
        " " + MemoryText.normalizedName(text) + " "
    }

    /// The names a thought can be found by, ready for whole-word search.
    /// A leading "the", "a", "an" or "my" is dropped, so "The launch" is found in "launch day".
    private static func searchNames(for thought: Thought) -> [String] {
        let articles: Set<String> = ["the", "a", "an", "my"]
        return ([thought.label] + thought.aliases).compactMap { name in
            var words = MemoryText.normalizedName(name).split(separator: " ").map(String.init)
            if let first = words.first, articles.contains(first), words.count > 1 {
                words.removeFirst()
            }
            let joined = words.joined(separator: " ")
            // Very short names match too much by accident.
            return joined.count >= 3 ? " " + joined + " " : nil
        }
    }

    // MARK: - What is sent for each thought

    private static func item(
        for thought: Thought,
        openEntry: UUID,
        included: Set<String>,
        labels: [String: String],
        limits: Limits
    ) -> TalkMemoryContext.Item {
        let quotes = thought.evidence
            .filter { $0.entryID != openEntry }
            .sorted { ($0.date, $0.quote) < ($1.date, $1.quote) }
            .suffix(limits.quotesPerThought)
            .map { TalkMemoryContext.Quote(date: $0.date, text: $0.quote) }

        let shifts = thought.timeline
            .filter { $0.entryID != openEntry }
            .sorted { ($0.date, $0.note) < ($1.date, $1.note) }
            .suffix(limits.shiftsPerThought)
            .map { TalkMemoryContext.Shift(date: $0.date, note: $0.note) }

        let connections = thought.links
            .filter { $0.entryID != openEntry && included.contains($0.target) }
            .sorted { ($0.target, $0.date) < ($1.target, $1.date) }
            .map { TalkMemoryContext.Connection(label: labels[$0.target] ?? $0.target, reason: $0.reason, date: $0.date, quote: $0.quote) }

        return TalkMemoryContext.Item(
            id: thought.id,
            label: thought.label,
            kind: thought.kind,
            summary: thought.summary,
            quotes: Array(quotes),
            shifts: Array(shifts),
            connections: connections
        )
    }

    /// What the entries behind the quotes were about, most recent last.
    private static func daySummaries(
        for items: [TalkMemoryContext.Item],
        chosen: [Thought],
        openEntry: UUID,
        digests: [EntryDigest],
        limits: Limits
    ) -> [TalkMemoryContext.DaySummary] {
        let sentQuotes = Set(items.flatMap { $0.quotes.map(\.text) })
        let cited = Set(chosen.flatMap(\.evidence).filter { $0.entryID != openEntry && sentQuotes.contains($0.quote) }.map(\.entryID))

        return digests
            .filter { cited.contains($0.entryID) && !$0.failed && !$0.summary.isEmpty }
            .sorted { ($0.entryDate, $0.entryID.uuidString) < ($1.entryDate, $1.entryID.uuidString) }
            .suffix(limits.daySummaries)
            .map { TalkMemoryContext.DaySummary(date: $0.entryDate, summary: $0.summary) }
    }

    private static func size(of context: TalkMemoryContext) -> Int {
        var total = context.profile.count
        for item in context.thoughts {
            total += item.label.count + item.summary.count
            total += item.quotes.reduce(0) { $0 + $1.text.count + 20 }
            total += item.shifts.reduce(0) { $0 + $1.note.count + 20 }
            total += item.connections.reduce(0) { $0 + $1.reason.count + $1.quote.count + $1.label.count + 20 }
        }
        total += context.days.reduce(0) { $0 + $1.summary.count + 20 }
        return total
    }
}
