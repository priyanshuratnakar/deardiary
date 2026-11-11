//
//  MemoryApplier.swift
//  Dear Diary
//
//  Decides what from a reading of one entry is allowed into memory, and in
//  what form.
//
//  The rules, in order of importance:
//  1. No invented evidence. Every item needs a quote that is found in the
//     entry; what is stored is the entry's own text, never the AI's copy.
//  2. The user's fixes win. Anything that conflicts with pins.json is refused.
//  3. Reuse before create. A person or topic that goes by a name already in
//     memory is attached to the existing thought.
//  4. Doing it twice changes nothing. Applying an entry first takes that
//     entry's earlier lines back out, so an edited entry never leaves
//     duplicates and a rebuild is always safe.
//
//  What becomes a thought (a dot on the map), and what stays on the day:
//  - People and topics become thoughts.
//  - Something that helped becomes a thought only if the entry itself puts it
//    with a pleasant feeling the writer named. The AI's word for it is not
//    enough.
//  - Something still open becomes a thought named by the writer's own line.
//  - Feelings, what happened, what they told themselves and what they wanted
//    stay on the day as lines (`DayLine`). A feeling becomes a thought later,
//    once the same words have been used on two days (`FeelingDots`).
//  - A link between two thoughts means one thing: the writer put them in the
//    same sentence. The app works that out; the AI is not asked.
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
    /// The reason recorded on a link the app made because two thoughts share a sentence.
    static let sameSentence = "in the same sentence"

    struct Outcome: Equatable {
        /// The thoughts this entry ended up touching.
        var touched: [String] = []
        /// What was refused, and why.
        var rejected: [EntryDigest.Rejection] = []
        /// The writer's own lines from this entry, to keep on its day.
        var lines: [DayLine] = []
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

    // MARK: - Putting a reading in

    static func apply(_ result: DigestResult, for entry: DigestedEntry, to memory: inout MemorySnapshot, pins: Pins) -> Outcome {
        remove(entryID: entry.id, from: &memory)

        var outcome = Outcome()
        var touched: Set<String> = []
        /// Every name already in memory (labels, other names, ids), pointing at its thought.
        var known: [String: String] = [:]
        for thought in memory.thoughts.values.sorted(by: { $0.id < $1.id }) {
            register(thought, in: &known)
        }
        /// What this entry attached to each thought, in order, for working out links.
        var attached: [(id: String, quote: String)] = []

        func reject(_ item: String, _ reason: String) {
            outcome.rejected.append(EntryDigest.Rejection(item: item, reason: reason))
        }

        func quote(_ text: String) -> String? {
            QuoteMatcher.locate(text, in: entry.text)
        }

        func keep(_ line: DayLine) {
            if !outcome.lines.contains(line) {
                outcome.lines.append(line)
            }
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

        /// Puts a line behind the thought that goes by this name, creating the thought if
        /// nothing in memory does. Returns the thought's id, or nil if it was refused.
        func attach(_ rawName: String, kind: ThoughtKind, quote rawQuote: String, item: String) -> String? {
            let label = MemoryText.singleLine(rawName)
            guard !label.isEmpty else {
                reject(item, "It had no name.")
                return nil
            }
            guard let evidence = quote(rawQuote) else {
                reject(item, "Its quote is not in the entry.")
                return nil
            }
            guard !pins.hasDeleted(name: label) else {
                reject(item, "You deleted this thought.")
                return nil
            }

            // Reuse before create: does anything in memory already go by this name?
            var targetID = (known[MemoryText.normalizedName(label)] ?? known[MemoryText.nameWithoutArticle(label)]).map(pins.resolve)
            // The user's fixes can also say where a name belongs (a thought they renamed, or folded into another).
            let pinnedID = pins.pinnedID(forName: label)
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
                    reject(item, "You deleted this thought.")
                    return nil
                }
                addEvidence(evidence, to: existingID)
                addAliases([label], to: existingID)
                attached.append((existingID, evidence))
                return existingID
            }

            var id = pinnedID ?? pins.resolve(MemoryText.slug(label))
            guard !pins.isDeleted(id) else {
                reject(item, "You deleted this thought.")
                return nil
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
                kind: kind,
                evidence: [Evidence(entryID: entry.id, date: entry.date, quote: evidence)]
            )
            memory.thoughts[id] = thought
            register(thought, in: &known)
            // If the user's name was used instead, the name from the entry stays on as another name for it.
            if thought.label != label {
                addAliases([label], to: id)
            }
            touched.insert(id)
            attached.append((id, evidence))
            return id
        }

        // 1. People and topics: the lasting things, by the names the writer uses.
        for person in result.people {
            _ = attach(person.name, kind: .person, quote: person.quote, item: "person")
        }
        for topic in result.topics {
            _ = attach(topic.name, kind: .topic, quote: topic.quote, item: "topic")
        }

        // 2. Feelings stay on the day. The word is kept only if it is the writer's own.
        let entryWords = " " + MemoryText.normalizedName(entry.text) + " "
        for feeling in result.feelings {
            guard let evidence = quote(feeling.quote) else {
                reject("feeling", "Its quote is not in the entry.")
                continue
            }
            let word = MemoryText.singleLine(feeling.word)
            let name = MemoryText.normalizedName(word)
            let isTheirWord = !name.isEmpty && entryWords.contains(" " + name + " ")
            keep(DayLine(kind: .felt, quote: evidence, word: isTheirWord ? word : nil, tone: feeling.tone))
        }

        // 3. What happened, what they told themselves, what they wanted: lines on the day.
        for item in result.happened {
            guard let evidence = quote(item.quote) else {
                reject("happened", "Its quote is not in the entry.")
                continue
            }
            keep(DayLine(kind: .happened, quote: evidence))
        }
        for line in result.selfTalk {
            guard let evidence = quote(line) else {
                reject("self_talk", "Its quote is not in the entry.")
                continue
            }
            keep(DayLine(kind: .toldYourself, quote: evidence))
        }
        for item in result.matters {
            guard let evidence = quote(item.quote) else {
                reject("matters", "Its quote is not in the entry.")
                continue
            }
            keep(DayLine(kind: .wanted, quote: evidence))
        }

        // 4. What helped. The AI's say-so is not enough: the entry itself has to put it
        //    with a pleasant feeling the writer named.
        let pleasant = outcome.lines
            .filter { $0.kind == .felt && $0.tone == .pleasant }
            .map { MemoryText.normalizedName($0.quote) }
            .filter { !$0.isEmpty }
        for item in result.helped {
            guard let evidence = quote(item.quote) else {
                reject("helped", "Its quote is not in the entry.")
                continue
            }
            let said = MemoryText.normalizedName(evidence)
            guard pleasant.contains(where: { said.contains($0) || $0.contains(said) }) else {
                reject("helped", "The entry does not say they felt better.")
                continue
            }
            if attach(item.what, kind: .helped, quote: evidence, item: "helped") != nil {
                keep(DayLine(kind: .helped, quote: evidence))
            }
        }

        // 5. What is still open, named by the writer's own line.
        for item in result.openLoops {
            guard let evidence = quote(item.quote) else {
                reject("open_loop", "Its quote is not in the entry.")
                continue
            }
            let label = openLabel(evidence)
            if pins.settled(forLine: label) != nil {
                // The user has closed this. Its line stays on the day; it does not come back to the map.
                keep(DayLine(kind: .stillOpen, quote: evidence))
                continue
            }
            if attach(label, kind: .open, quote: evidence, item: "open_loop") != nil {
                keep(DayLine(kind: .stillOpen, quote: evidence))
            }
        }

        // 6. Links: two thoughts the writer put in the same sentence.
        for first in attached.indices {
            for second in attached.indices where second > first {
                let one = attached[first], other = attached[second]
                guard one.id != other.id,
                      let thoughtOne = memory.thoughts[one.id], let thoughtOther = memory.thoughts[other.id],
                      let together = sentenceShared(one.quote, thoughtOne, other.quote, thoughtOther) else {
                    continue
                }
                let from = min(one.id, other.id), to = max(one.id, other.id)
                guard !pins.isLinkRemoved(from, to) else {
                    reject("link", "You removed this link.")
                    continue
                }
                // One link per pair from each entry.
                guard memory.thoughts[from]?.links.contains(where: { $0.target == to && $0.entryID == entry.id }) == false else {
                    continue
                }
                memory.thoughts[from]?.links.append(ThoughtLink(target: to, reason: sameSentence, entryID: entry.id, date: entry.date, quote: together))
            }
        }

        // 7. The user's fixes have the last word.
        MemoryFixes.enforce(pins, on: &memory)

        outcome.touched = touched.filter { memory.thoughts[$0] != nil }.sorted()
        return outcome
    }

    /// The name of something still open: the writer's own line, on one line, without its
    /// closing full stop, and not too long to read on the map's panel.
    static func openLabel(_ quote: String) -> String {
        var label = MemoryText.singleLine(quote)
        while let last = label.last, ".!?,;:".contains(last) {
            label.removeLast()
        }
        if label.count > 90 {
            label = String(label.prefix(90)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return label
    }

    /// The sentence two thoughts share, if the writer put them in one: either their two
    /// lines are the same line (or one inside the other), or one's line names the other.
    private static func sentenceShared(_ firstQuote: String, _ first: Thought, _ secondQuote: String, _ second: Thought) -> String? {
        let one = MemoryText.normalizedName(firstQuote)
        let other = MemoryText.normalizedName(secondQuote)
        guard !one.isEmpty, !other.isEmpty else { return nil }
        if one.contains(other) { return firstQuote }
        if other.contains(one) { return secondQuote }
        if names(of: second).contains(where: { (" " + one + " ").contains(" " + $0 + " ") }) { return firstQuote }
        if names(of: first).contains(where: { (" " + other + " ").contains(" " + $0 + " ") }) { return secondQuote }
        return nil
    }

    /// The names a thought can be found by inside a sentence. Very short names match too much by accident.
    private static func names(of thought: Thought) -> [String] {
        ([thought.label] + thought.aliases)
            .map(MemoryText.nameWithoutArticle)
            .filter { $0.count >= 3 }
    }

    private static func register(_ thought: Thought, in known: inout [String: String]) {
        for name in [thought.label, thought.id] + thought.aliases {
            for form in [MemoryText.normalizedName(name), MemoryText.nameWithoutArticle(name)] {
                if !form.isEmpty, known[form] == nil {
                    known[form] = thought.id
                }
            }
        }
    }
}

/// Feelings that have become thoughts.
///
/// A feeling is kept on its day, in the writer's own word. When the same word has been
/// used on two or more days it becomes a thought, so the days it was named on can be seen
/// together. The app decides this by counting; the AI is not asked to group feelings.
enum FeelingDots {
    /// The start of the id (and so of the note's file name) of a feeling that became a thought this way.
    static let prefix = "felt-"

    /// Words in front of a feeling that do not change which feeling it is.
    private static let leading: Set<String> = ["i", "felt", "feel", "feeling", "was", "so", "very", "really", "a", "bit", "quite", "just"]

    /// What two uses of a feeling are compared by: "so tired" and "tired" are the same feeling.
    static func key(_ word: String) -> String {
        var words = MemoryText.normalizedName(word).split(separator: " ").map(String.init)
        while words.count > 1, let first = words.first, leading.contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    static func id(forKey key: String) -> String {
        prefix + MemoryText.slug(key)
    }

    /// Makes the feeling thoughts agree with the lines kept on every day: a feeling named
    /// in the same words on two or more days has a thought with those lines behind it,
    /// and one that no longer is does not. Fixes are obeyed.
    static func reconcile(_ memory: inout MemorySnapshot, with digests: [EntryDigest], pins: Pins) {
        struct Use {
            let entryID: UUID
            let date: String
            let quote: String
            let word: String
        }

        var uses: [String: [Use]] = [:]
        for digest in digests where !digest.failed {
            for line in digest.lines ?? [] where line.kind == .felt {
                guard let word = line.word else { continue }
                let key = key(word)
                guard !key.isEmpty else { continue }
                uses[key, default: []].append(Use(entryID: digest.entryID, date: digest.entryDate, quote: line.quote, word: word))
            }
        }

        var standing: Set<String> = []
        for (key, found) in uses.sorted(by: { $0.key < $1.key }) {
            guard Set(found.map(\.entryID)).count >= 2 else { continue }
            let ordered = found.sorted { ($0.date, $0.entryID.uuidString, $0.quote) < ($1.date, $1.entryID.uuidString, $1.quote) }
            let ownID = id(forKey: key)
            let words = MemoryFixes.unique(ordered.map(\.word), excluding: "")
            guard !pins.isDeleted(ownID), !words.contains(where: pins.hasDeleted(name:)) else { continue }

            // If the user folded this feeling into another thought, its lines go there.
            let target = pins.resolve(ownID)
            let id = memory.thoughts[target] != nil ? target : ownID
            var thought = memory.thoughts[id] ?? Thought(id: id, label: pins.pinnedLabel(for: id) ?? words[0], kind: .feeling)
            for use in ordered {
                let item = Evidence(entryID: use.entryID, date: use.date, quote: use.quote)
                if !thought.evidence.contains(item) {
                    thought.evidence.append(item)
                }
            }
            thought.aliases = MemoryFixes.unique(thought.aliases + words, excluding: thought.label)
            memory.thoughts[id] = thought
            standing.insert(id)
        }

        // A feeling thought left with lines from fewer than two days goes back to being lines on a day.
        for (id, thought) in memory.thoughts where id.hasPrefix(prefix) && thought.kind == .feeling && !standing.contains(id) {
            if Set(thought.evidence.map(\.entryID)).count < 2 {
                memory.thoughts[id] = nil
            }
        }

        MemoryFixes.enforce(pins, on: &memory)
    }

    /// The feeling thoughts that hold a line from this entry.
    static func touched(by entryID: UUID, in memory: MemorySnapshot) -> [String] {
        memory.thoughts.values
            .filter { $0.kind == .feeling && $0.id.hasPrefix(prefix) && $0.evidence.contains { $0.entryID == entryID } }
            .map(\.id)
            .sorted()
    }
}
