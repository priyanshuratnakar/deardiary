//
//  MemoryFixes.swift
//  Dear Diary
//
//  The user's manual fixes to memory: rename a thought, fold one thought into
//  another, delete a thought, add a link by hand, remove a link, and close
//  something that was still open (done, or not doing it).
//
//  Each fix does two things: it changes memory now, and it is written into
//  the fixes file (pins.json) so the AI can never undo it, not in a later
//  digest and not in a full rebuild.
//
//  This file only works on data in hand. It does not read or write files.
//

import Foundation

enum MemoryFix: Equatable {
    case rename(id: String, to: String)
    /// Fold `from` into `into`: its lines, links and names move over, and it is gone.
    case merge(from: String, into: String)
    case delete(id: String)
    case addLink(from: String, to: String, reason: String)
    case removeLink(String, String)
    /// Close something that was still open. It leaves the map and does not come back;
    /// its line stays on its day. `on` is the day it was closed, as yyyy-MM-dd.
    case settle(id: String, as: Pins.Settled, on: String)
}

enum MemoryFixes {
    /// Makes the fix and records it. Returns false, changing nothing, if the fix
    /// does not make sense (a thought that is not there, an empty name, and so on).
    @discardableResult
    static func apply(_ fix: MemoryFix, to memory: inout MemorySnapshot, pins: inout Pins) -> Bool {
        switch fix {
        case .rename(let id, let newName):
            let label = MemoryText.singleLine(newName)
            guard let thought = memory.thoughts[id], !label.isEmpty, label != thought.label else {
                return false
            }
            let earlier = pins.renames.filter { $0.id == id }.flatMap { [$0.label] + ($0.names ?? []) }
            pins.renames.removeAll { $0.id == id }
            pins.renames.append(Pins.Rename(id: id, label: label, names: unique([thought.label] + thought.aliases + earlier, excluding: label)))
            // The old name stays on as one of its other names, so it can still be found by it.
            memory.thoughts[id]?.aliases = unique(thought.aliases + [thought.label], excluding: label)
            memory.thoughts[id]?.label = label

        case .merge(let from, let into):
            guard from != into, let source = memory.thoughts[from], let target = memory.thoughts[into] else {
                return false
            }
            let earlier = pins.renames.filter { $0.id == from }.flatMap { [$0.label] + ($0.names ?? []) }
            pins.renames.removeAll { $0.id == from }
            pins.merges.removeAll { $0.from == from }
            pins.merges.append(Pins.Merge(
                from: from,
                into: into,
                names: unique([source.label] + source.aliases + earlier, excluding: ""),
                intoLabel: target.label
            ))
            // Links the user made to or from the folded thought now belong to the other one.
            pins.linksAdded = pins.linksAdded.compactMap { link in
                var moved = link
                if moved.from == from { moved.from = into }
                if moved.to == from { moved.to = into }
                return moved.from == moved.to ? nil : moved
            }
            fold(from, into: into, in: &memory)

        case .delete(let id):
            guard let thought = memory.thoughts[id] else {
                return false
            }
            pins.deletions.removeAll { $0.id == id }
            pins.deletions.append(Pins.Deletion(id: id, label: thought.label, names: thought.aliases))
            pins.renames.removeAll { $0.id == id }
            pins.linksAdded.removeAll { $0.from == id || $0.to == id }

        case .settle(let id, let how, let day):
            guard let thought = memory.thoughts[id], thought.kind == .open else {
                return false
            }
            // Kept with the deletions, so every rule that keeps a deleted thought from coming
            // back also keeps a closed one from coming back. Its names include the writer's
            // own lines, so those lines can be shown as done on their days.
            let earlier = pins.renames.filter { $0.id == id }.flatMap { [$0.label] + ($0.names ?? []) }
            let lines = thought.evidence.map { MemoryApplier.openLabel($0.quote) }
            pins.deletions.removeAll { $0.id == id }
            pins.deletions.append(Pins.Deletion(
                id: id,
                label: thought.label,
                names: unique(thought.aliases + earlier + lines, excluding: thought.label),
                settled: how.rawValue,
                on: day
            ))
            pins.renames.removeAll { $0.id == id }
            pins.linksAdded.removeAll { $0.from == id || $0.to == id }

        case .addLink(let from, let to, let reason):
            let text = MemoryText.singleLine(reason)
            guard from != to, memory.thoughts[from] != nil, memory.thoughts[to] != nil, !text.isEmpty else {
                return false
            }
            // Adding a link back means the earlier removal no longer stands.
            pins.linksRemoved.removeAll { isPair($0, from, to) }
            pins.linksAdded.removeAll { isPair($0, from, to) }
            pins.linksAdded.append(Pins.LinkPin(from: from, to: to, reason: text))

        case .removeLink(let first, let second):
            guard first != second, memory.thoughts[first] != nil, memory.thoughts[second] != nil else {
                return false
            }
            let madeByUser = pins.linksAdded.contains { isPair($0, first, second) }
            let madeByAI = (memory.thoughts[first]?.links.contains { $0.target == second } ?? false)
                || (memory.thoughts[second]?.links.contains { $0.target == first } ?? false)
            guard madeByUser || madeByAI else {
                return false
            }
            pins.linksAdded.removeAll { isPair($0, first, second) }
            if madeByAI, !pins.isLinkRemoved(first, second) {
                pins.linksRemoved.append(Pins.LinkPin(from: first, to: second, reason: nil))
            }
        }

        enforce(pins, on: &memory)
        return true
    }

    /// Makes memory agree with the fixes file. This runs after every digest and
    /// every tidy, so the user's fixes always have the last word.
    static func enforce(_ pins: Pins, on memory: inout MemorySnapshot) {
        // 1. Thoughts the user folded away go into the thought they joined.
        for merge in pins.merges where memory.thoughts[merge.from] != nil {
            let target = pins.resolve(merge.from)
            guard target != merge.from, !pins.isDeleted(target) else { continue }
            if memory.thoughts[target] == nil, var moved = memory.thoughts[merge.from] {
                // The thought it joined is not there (yet): it takes that place and name.
                moved.aliases = unique(moved.aliases + [moved.label], excluding: pins.mergeTargetLabel(for: target) ?? moved.label)
                moved.label = pins.mergeTargetLabel(for: target) ?? moved.label
                moved.id = target
                memory.thoughts[merge.from] = nil
                memory.thoughts[target] = moved
                retarget(merge.from, to: target, in: &memory)
            } else {
                fold(merge.from, into: target, in: &memory)
            }
        }

        // 2. Deleted thoughts are gone, along with links that pointed at them.
        let deleted = Set(memory.thoughts.keys.filter(pins.isDeleted))
        for id in deleted {
            memory.thoughts[id] = nil
        }
        if !deleted.isEmpty {
            for id in memory.thoughts.keys {
                memory.thoughts[id]?.links.removeAll { deleted.contains($0.target) }
            }
        }

        // 3. Renamed thoughts keep the user's name.
        for id in memory.thoughts.keys {
            guard let pinned = pins.pinnedLabel(for: id), let thought = memory.thoughts[id], thought.label != pinned else { continue }
            memory.thoughts[id]?.aliases = unique(thought.aliases + [thought.label], excluding: pinned)
            memory.thoughts[id]?.label = pinned
        }

        // 4. Links the user removed stay removed.
        for id in memory.thoughts.keys {
            memory.thoughts[id]?.links.removeAll { pins.isLinkRemoved(id, $0.target) }
        }

        // 5. Links the user made are on the thought they start from.
        for id in memory.thoughts.keys {
            var links: [UserLink] = []
            for pin in pins.linksAdded {
                let from = pins.resolve(pin.from)
                let to = pins.resolve(pin.to)
                guard from == id, to != id, memory.thoughts[to] != nil else { continue }
                let reason = MemoryText.singleLine(pin.reason ?? "")
                if !links.contains(where: { $0.target == to }) {
                    links.append(UserLink(target: to, reason: reason))
                }
            }
            if memory.thoughts[id]?.userLinks != links {
                memory.thoughts[id]?.userLinks = links
            }
        }
    }

    /// Moves everything one thought holds into another and removes the first.
    /// Used for the user's merges and for duplicates the weekly tidy finds.
    static func fold(_ from: String, into: String, in memory: inout MemorySnapshot) {
        guard from != into, let source = memory.thoughts[from], var target = memory.thoughts[into] else {
            return
        }

        for item in source.evidence where !target.evidence.contains(item) {
            target.evidence.append(item)
        }
        for note in source.timeline where !target.timeline.contains(note) {
            target.timeline.append(note)
        }
        for link in source.links where link.target != into && !target.links.contains(link) {
            target.links.append(link)
        }
        // A link from the thought it joined back to the folded one would now point at itself.
        target.links.removeAll { $0.target == from }
        target.aliases = unique(target.aliases + [source.label] + source.aliases, excluding: target.label)
        if target.summary.isEmpty {
            target.summary = source.summary
        }

        memory.thoughts[into] = target
        memory.thoughts[from] = nil
        retarget(from, to: into, in: &memory)
    }

    /// Points every link that led to one thought at another instead.
    private static func retarget(_ old: String, to new: String, in memory: inout MemorySnapshot) {
        for id in memory.thoughts.keys {
            guard var thought = memory.thoughts[id], thought.links.contains(where: { $0.target == old }) else { continue }
            thought.links = thought.links.compactMap { link in
                guard link.target == old else { return link }
                guard id != new else { return nil }
                var moved = link
                moved.target = new
                return moved
            }
            memory.thoughts[id] = thought
        }
    }

    private static func isPair(_ link: Pins.LinkPin, _ first: String, _ second: String) -> Bool {
        (link.from == first && link.to == second) || (link.from == second && link.to == first)
    }

    /// Names without repeats (comparing as names are compared everywhere else), leaving one name out.
    static func unique(_ names: [String], excluding excluded: String) -> [String] {
        var seen: Set<String> = [MemoryText.normalizedName(excluded)]
        var result: [String] = []
        for name in names.map(MemoryText.singleLine) {
            let key = MemoryText.normalizedName(name)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(name)
        }
        return result
    }
}
