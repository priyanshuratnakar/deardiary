//
//  MemoryApplier.swift
//  Dear Diary
//
//  Decides what from an AI digest is allowed into memory.
//
//  The rules, in order of importance:
//  1. No invented evidence. Every item needs a quote that is found in the
//     entry; what is stored is the entry's own text, never the AI's copy.
//  2. The user's fixes win. Anything that conflicts with pins.json is refused.
//  3. Reuse before create. A "new" thought that goes by a name already in
//     memory is attached to the existing thought.
//  4. Doing it twice changes nothing. Applying an entry first takes that
//     entry's earlier lines back out, so an edited entry never leaves
//     duplicates and a rebuild is always safe.
//
//  This file only works on data in hand. It does not read or write files.
//

import Foundation

/// The entry a digest was made from.
struct DigestedEntry: Equatable {
    let id: UUID
    /// The day the entry was started, as yyyy-MM-dd.
    let date: String
    let text: String
}

enum MemoryApplier {
    struct Outcome: Equatable {
        /// The thoughts this entry ended up touching.
        var touched: [String] = []
        /// What was refused, and why.
        var rejected: [EntryDigest.Rejection] = []
    }

    // MARK: - Taking an entry back out

    /// Removes every line that came from one entry. Thoughts left with no
    /// evidence at all are removed too, along with links that pointed at them.
    static func remove(entryID: UUID, from memory: inout MemorySnapshot) {
        for id in memory.thoughts.keys {
            guard var thought = memory.thoughts[id] else { continue }
            thought.evidence.removeAll { $0.entryID == entryID }
            thought.timeline.removeAll { $0.entryID == entryID }
            thought.links.removeAll { $0.entryID == entryID }
            memory.thoughts[id] = thought
        }
        dropThoughts(where: { !$0.hasEvidence }, from: &memory)
    }

    private static func dropThoughts(where shouldDrop: (Thought) -> Bool, from memory: inout MemorySnapshot) {
        let gone = Set(memory.thoughts.values.filter(shouldDrop).map(\.id))
        guard !gone.isEmpty else { return }
        for id in gone {
            memory.thoughts[id] = nil
        }
        for id in memory.thoughts.keys {
            memory.thoughts[id]?.links.removeAll { gone.contains($0.target) }
        }
    }

    // MARK: - Putting a digest in

    static func apply(_ result: DigestResult, for entry: DigestedEntry, to memory: inout MemorySnapshot, pins: Pins) -> Outcome {
        remove(entryID: entry.id, from: &memory)

        var outcome = Outcome()
        var touched: Set<String> = []
        /// Names of thoughts created in this reply, so links and notes can refer to them.
        var createdByName: [String: String] = [:]
        /// Every name already in memory (labels, other names, ids), pointing at its thought.
        var known: [String: String] = [:]
        for thought in memory.thoughts.values.sorted(by: { $0.id < $1.id }) {
            register(thought, in: &known)
        }

        func reject(_ item: String, _ reason: String) {
            outcome.rejected.append(EntryDigest.Rejection(item: item, reason: reason))
        }

        func quote(_ text: String) -> String? {
            QuoteMatcher.locate(text, in: entry.text)
        }

        /// Finds the thought a reply is pointing at: an id, a name created in this
        /// reply, or a name already in memory. Fixes are honoured along the way.
        func resolve(_ reference: String) -> String? {
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !pins.isDeleted(trimmed) else { return nil }

            let direct = pins.resolve(trimmed)
            if !pins.isDeleted(direct), memory.thoughts[direct] != nil {
                return direct
            }
            let name = MemoryText.normalizedName(trimmed)
            if let created = createdByName[name] {
                return created
            }
            if let existing = known[name] {
                let resolved = pins.resolve(existing)
                if !pins.isDeleted(resolved), memory.thoughts[resolved] != nil {
                    return resolved
                }
            }
            return nil
        }

        func addEvidence(_ text: String, to id: String) {
            guard var thought = memory.thoughts[id] else { return }
            if !thought.evidence.contains(where: { $0.entryID == entry.id && $0.quote == text }) {
                thought.evidence.append(Evidence(entryID: entry.id, date: entry.date, quote: text))
            }
            memory.thoughts[id] = thought
            touched.insert(id)
        }

        func addAliases(_ aliases: [String], to id: String) {
            guard var thought = memory.thoughts[id] else { return }
            var taken = Set(([thought.label] + thought.aliases).map(MemoryText.normalizedName))
            for alias in aliases.map(MemoryText.singleLine) {
                let name = MemoryText.normalizedName(alias)
                guard !name.isEmpty, !taken.contains(name) else { continue }
                thought.aliases.append(alias)
                taken.insert(name)
                if known[name] == nil {
                    known[name] = id
                }
            }
            memory.thoughts[id] = thought
        }

        // 1. New thoughts first, so that links and notes can point at them.
        for new in result.newThoughts {
            let label = MemoryText.singleLine(new.label)
            guard !label.isEmpty else {
                reject("new_thought", "It had no name.")
                continue
            }
            guard let evidence = quote(new.quote) else {
                reject("new_thought", "Its quote is not in the entry.")
                continue
            }
            let names = [label] + new.aliases
            guard !names.contains(where: pins.hasDeleted(name:)) else {
                reject("new_thought", "You deleted this thought.")
                continue
            }

            // Reuse before create: does anything in memory already go by one of these names?
            var targetID = names.lazy.compactMap { known[MemoryText.normalizedName($0)] }.first.map(pins.resolve)
            // The user's fixes can also say where a name belongs (a thought they renamed, or folded into another).
            let pinnedID = names.lazy.compactMap(pins.pinnedID(forName:)).first
            if targetID == nil, let pinnedID, memory.thoughts[pinnedID] != nil {
                targetID = pinnedID
            }
            if targetID == nil {
                // Same file name as an existing thought, or one the user merged away: use that thought.
                let slug = pins.resolve(MemoryText.slug(label))
                if memory.thoughts[slug] != nil {
                    targetID = slug
                }
            }

            if let existingID = targetID, memory.thoughts[existingID] != nil {
                guard !pins.isDeleted(existingID) else {
                    reject("new_thought", "You deleted this thought.")
                    continue
                }
                addEvidence(evidence, to: existingID)
                addAliases(names, to: existingID)
                createdByName[MemoryText.normalizedName(label)] = existingID
                continue
            }

            var id = pinnedID ?? pins.resolve(MemoryText.slug(label))
            guard !pins.isDeleted(id) else {
                reject("new_thought", "You deleted this thought.")
                continue
            }
            // Never reuse the file name of a note that could not be read.
            var suffix = 2
            let base = id
            while memory.unreadableIDs.contains(id) || memory.thoughts[id] != nil {
                id = "\(base)-\(suffix)"
                suffix += 1
            }

            let thought = Thought(
                id: id,
                label: pins.pinnedLabel(for: id) ?? pins.mergeTargetLabel(for: id) ?? label,
                kind: new.kind,
                aliases: [],
                summary: MemoryText.singleLine(new.summary),
                evidence: [Evidence(entryID: entry.id, date: entry.date, quote: evidence)]
            )
            memory.thoughts[id] = thought
            register(thought, in: &known)
            // If the user's name was used instead, the AI's name stays on as another name for it.
            addAliases(thought.label == label ? new.aliases : [label] + new.aliases, to: id)
            createdByName[MemoryText.normalizedName(label)] = id
            touched.insert(id)
        }

        // 2. More evidence for thoughts already in memory.
        for update in result.thoughtUpdates {
            let reference = update.thoughtID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pins.isDeleted(reference), !pins.isDeleted(pins.resolve(reference)) else {
                reject("thought_update", "You deleted this thought.")
                continue
            }
            guard let id = resolve(reference) else {
                reject("thought_update", "It named a thought that is not in memory.")
                continue
            }
            guard let evidence = quote(update.quote) else {
                reject("thought_update", "Its quote is not in the entry.")
                continue
            }
            addEvidence(evidence, to: id)
            if let summary = update.newSummary.map(MemoryText.singleLine), !summary.isEmpty {
                memory.thoughts[id]?.summary = summary
            }
            if let alias = update.newAlias {
                addAliases([alias], to: id)
            }
        }

        // 3. Notes on how a thought shifted.
        for note in result.timelineNotes {
            guard let id = resolve(note.thought) else {
                reject("timeline_note", "It named a thought that is not in memory.")
                continue
            }
            let text = MemoryText.singleLine(note.note)
            guard !text.isEmpty else {
                reject("timeline_note", "It had no text.")
                continue
            }
            guard let evidence = quote(note.quote) else {
                reject("timeline_note", "Its quote is not in the entry.")
                continue
            }
            if memory.thoughts[id]?.timeline.contains(where: { $0.entryID == entry.id && $0.note == text }) == false {
                memory.thoughts[id]?.timeline.append(TimelineNote(entryID: entry.id, date: entry.date, note: text, quote: evidence))
            }
            touched.insert(id)
        }

        // 4. Links between thoughts.
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
            guard let evidence = quote(link.quote) else {
                reject("link", "Its quote is not in the entry.")
                continue
            }
            // One link per pair from each entry: a later one replaces an earlier one.
            memory.thoughts[from]?.links.removeAll { $0.target == to && $0.entryID == entry.id }
            memory.thoughts[from]?.links.append(ThoughtLink(target: to, reason: reason, entryID: entry.id, date: entry.date, quote: evidence))
            touched.insert(from)
            touched.insert(to)
        }

        // 5. The profile, if the entry changed the picture.
        if let profile = result.profile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty {
            memory.profile = profile
        }

        // 6. The user's fixes have the last word.
        MemoryFixes.enforce(pins, on: &memory)

        outcome.touched = touched.filter { memory.thoughts[$0] != nil }.sorted()
        return outcome
    }

    private static func register(_ thought: Thought, in known: inout [String: String]) {
        for name in [thought.label, thought.id] + thought.aliases {
            let normalised = MemoryText.normalizedName(name)
            if !normalised.isEmpty, known[normalised] == nil {
                known[normalised] = thought.id
            }
        }
    }
}
