//
//  MemoryTidier.swift
//  Dear Diary
//
//  Decides what from the weekly tidy is allowed to change memory.
//
//  The tidy looks across all of memory, so it can do more than a digest:
//  merge duplicates, retire one-offs, and add patterns that only show across
//  several entries. Nothing is taken on trust:
//
//  - A merge needs both thoughts to exist, and never folds away a thought the
//    user renamed or linked by hand.
//  - "Retire" is only a suggestion. The app's own rule decides: the thought
//    appears in exactly one entry, that entry is more than three weeks old,
//    and the user has not renamed or linked it. A retired thought can come
//    back if the topic returns.
//  - A pattern or a cross-week link needs quoted lines from at least two
//    different entries, each checked against the entry it cites. What is
//    stored is the entry's own text.
//  - The user's fixes have the last word, as always.
//
//  This file only works on data in hand. It does not read or write files.
//

import Foundation

enum MemoryTidier {
    struct Rules {
        /// A thought seen in one entry can be retired once that entry is this many days old.
        var oneOffAfterDays = 21
        /// A pattern or cross-week link needs quotes from at least this many different entries.
        var entriesNeeded = 2
    }

    struct Outcome: Equatable {
        var merged = 0
        var retired = 0
        var patterns = 0
        var links = 0
        var profileRefreshed = false
        /// What was refused, and why.
        var rejected: [EntryDigest.Rejection] = []

        /// What the tidy did, in a few plain words.
        var line: String {
            var parts: [String] = []
            if merged > 0 { parts.append("merged \(merged)") }
            if retired > 0 { parts.append("retired \(retired)") }
            if patterns > 0 { parts.append("\(patterns) \(patterns == 1 ? "pattern" : "patterns") across weeks") }
            if links > 0 { parts.append("\(links) new \(links == 1 ? "link" : "links")") }
            if profileRefreshed { parts.append("refreshed the profile") }
            return parts.isEmpty ? "nothing needed changing" : parts.joined(separator: ", ")
        }
    }

    /// - Parameters:
    ///   - entry: looks up an entry by id, so quotes can be checked against it. Nil if the entry is gone.
    ///   - today: the current day, as yyyy-MM-dd.
    static func apply(
        _ result: TidyResult,
        to memory: inout MemorySnapshot,
        pins: Pins,
        entry: (UUID) -> DigestedEntry?,
        today: String,
        rules: Rules = Rules()
    ) -> Outcome {
        var outcome = Outcome()
        /// Thoughts folded away in this tidy, and where they went.
        var folded: [String: String] = [:]
        /// Patterns created in this reply, by name, so links can point at them.
        var createdByName: [String: String] = [:]

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

        /// Checks quotes against the entries they cite and returns the entries' own text.
        func verified(_ quotes: [TidyResult.Quote]) -> [Evidence] {
            var found: [Evidence] = []
            for quote in quotes {
                guard let id = UUID(uuidString: quote.entryID.trimmingCharacters(in: CharacterSet(charactersIn: "[] \n\t"))),
                      let source = entry(id),
                      let text = QuoteMatcher.locate(quote.quote, in: source.text) else {
                    continue
                }
                let item = Evidence(entryID: id, date: source.date, quote: text)
                if !found.contains(item) {
                    found.append(item)
                }
            }
            return found
        }

        func enoughEntries(_ evidence: [Evidence]) -> Bool {
            Set(evidence.map(\.entryID)).count >= rules.entriesNeeded
        }

        // 1. Duplicates.
        for merge in result.merges {
            let from = current(merge.from)
            let into = current(merge.into)
            guard memory.thoughts[from] != nil, memory.thoughts[into] != nil else {
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

        // 3. Patterns across weeks.
        var known = nameIndex(memory)
        for pattern in result.patterns {
            let label = MemoryText.singleLine(pattern.label)
            guard !label.isEmpty else {
                reject("pattern", "It had no name.")
                continue
            }
            guard !pins.hasDeleted(name: label) else {
                reject("pattern", "You deleted this thought.")
                continue
            }
            let evidence = verified(pattern.evidence)
            guard enoughEntries(evidence) else {
                reject("pattern", "It needs quoted lines from at least \(rules.entriesNeeded) entries.")
                continue
            }

            let name = MemoryText.normalizedName(label)
            let existing = (known[name].map(current) ?? pins.pinnedID(forName: label)).flatMap { memory.thoughts[$0] == nil ? nil : $0 }
            if let id = existing {
                for item in evidence where memory.thoughts[id]?.evidence.contains(item) == false {
                    memory.thoughts[id]?.evidence.append(item)
                }
                createdByName[name] = id
                outcome.patterns += 1
                continue
            }

            var id = pins.pinnedID(forName: label) ?? pins.resolve(MemoryText.slug(label))
            guard !pins.isDeleted(id) else {
                reject("pattern", "You deleted this thought.")
                continue
            }
            var suffix = 2
            let base = id
            while memory.unreadableIDs.contains(id) || memory.thoughts[id] != nil {
                id = "\(base)-\(suffix)"
                suffix += 1
            }
            memory.thoughts[id] = Thought(
                id: id,
                label: pins.pinnedLabel(for: id) ?? label,
                kind: pattern.kind,
                summary: MemoryText.singleLine(pattern.summary),
                evidence: evidence
            )
            known[name] = id
            createdByName[name] = id
            outcome.patterns += 1
        }

        // 4. Links that show across weeks.
        func resolve(_ reference: String) -> String? {
            let direct = current(reference)
            if !pins.isDeleted(direct), memory.thoughts[direct] != nil {
                return direct
            }
            let name = MemoryText.normalizedName(reference)
            if let created = createdByName[name] {
                return created
            }
            if let id = known[name].map(current), !pins.isDeleted(id), memory.thoughts[id] != nil {
                return id
            }
            return nil
        }

        for link in result.links {
            guard let from = resolve(link.from), let to = resolve(link.to) else {
                reject("link", "It named a thought that is not in memory.")
                continue
            }
            guard from != to else {
                reject("link", "It linked a thought to itself.")
                continue
            }
            guard !pins.isLinkRemoved(from, to) else {
                reject("link", "You removed this link.")
                continue
            }
            let reason = MemoryText.singleLine(link.reason)
            guard !reason.isEmpty else {
                reject("link", "It gave no reason.")
                continue
            }
            let evidence = verified(link.evidence)
            guard enoughEntries(evidence) else {
                reject("link", "It needs quoted lines from at least \(rules.entriesNeeded) entries.")
                continue
            }
            for item in evidence {
                memory.thoughts[from]?.links.removeAll { $0.target == to && $0.entryID == item.entryID }
                memory.thoughts[from]?.links.append(ThoughtLink(target: to, reason: reason, entryID: item.entryID, date: item.date, quote: item.quote))
            }
            outcome.links += 1
        }

        // 5. The profile.
        if let profile = result.profile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty, profile != memory.profile {
            memory.profile = profile
            outcome.profileRefreshed = true
        }

        // 6. The user's fixes have the last word.
        MemoryFixes.enforce(pins, on: &memory)
        return outcome
    }

    /// Every name in memory (labels, other names, ids), pointing at its thought.
    private static func nameIndex(_ memory: MemorySnapshot) -> [String: String] {
        var known: [String: String] = [:]
        for thought in memory.thoughts.values.sorted(by: { $0.id < $1.id }) {
            for name in [thought.label, thought.id] + thought.aliases {
                let normalised = MemoryText.normalizedName(name)
                if !normalised.isEmpty, known[normalised] == nil {
                    known[normalised] = thought.id
                }
            }
        }
        return known
    }

    /// The day a number of days before another, both as yyyy-MM-dd.
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
