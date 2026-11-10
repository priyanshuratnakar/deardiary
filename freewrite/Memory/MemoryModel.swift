//
//  MemoryModel.swift
//  Dear Diary
//
//  The shapes memory is made of: thoughts, the evidence behind them, the
//  digest kept for each entry, and the user's manual fixes ("pins").
//
//  Everything here is plain data. Reading and writing files is in
//  MemoryStore; deciding what goes in is in MemoryApplier.
//

import Foundation

/// What kind of thing a thought is. The map colours nodes by this.
enum ThoughtKind: String, CaseIterable, Codable {
    case theme
    case feeling
    case person
    case idea
    case question
    case decision
    case event

    /// Accepts any capitalisation and stray spaces, because that is not guaranteed in model output.
    init?(loose text: String) {
        self.init(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// A line quoted from an entry. The quote is always the entry's exact text.
struct Evidence: Equatable {
    var entryID: UUID
    /// The day the entry was started, as yyyy-MM-dd.
    var date: String
    var quote: String
}

/// A dated note on how a thought has shifted, with the line that shows it.
struct TimelineNote: Equatable {
    var entryID: UUID
    var date: String
    var note: String
    var quote: String
}

/// A connection from one thought to another, with a reason and the line that shows it.
struct ThoughtLink: Equatable {
    /// The id of the thought this one is connected to.
    var target: String
    var reason: String
    var entryID: UUID
    var date: String
    var quote: String
}

/// A connection the user made by hand on the map. It has no quoted line behind it,
/// so it is kept apart from the AI's links and is never shown as evidence.
struct UserLink: Equatable {
    var target: String
    var reason: String
}

struct Thought: Equatable {
    /// A readable name that is also the note's file name, such as "saying-yes-under-pressure".
    var id: String
    var label: String
    var kind: ThoughtKind
    /// Other names it goes by.
    var aliases: [String] = []
    /// A sentence or two on what this is.
    var summary: String = ""
    var timeline: [TimelineNote] = []
    var evidence: [Evidence] = []
    var links: [ThoughtLink] = []
    /// Links the user added by hand.
    var userLinks: [UserLink] = []

    private var allDates: [String] {
        evidence.map(\.date) + timeline.map(\.date) + links.map(\.date)
    }

    var firstSeen: String? { allDates.min() }
    var lastSeen: String? { allDates.max() }

    /// A thought with no quoted line behind it has no place in memory.
    var hasEvidence: Bool { !evidence.isEmpty }
}

/// Everything the AI has built, as it is in memory while being worked on.
struct MemorySnapshot: Equatable {
    var thoughts: [String: Thought] = [:]
    var profile: String = ""
    /// File names of thought notes that could not be read (for example after a
    /// hand edit). They are left alone and their names are never reused.
    var unreadableIDs: Set<String> = []
}

/// What is kept about one entry after it has been digested.
struct EntryDigest: Codable, Equatable {
    struct Rejection: Codable, Equatable {
        /// Which kind of item was turned down, such as "new_thought" or "link".
        var item: String
        /// Why, in plain words. Never contains entry text.
        var reason: String
    }

    var entryID: UUID
    /// The day the entry was started, as yyyy-MM-dd.
    var entryDate: String
    /// A fingerprint of the entry text. If it matches, the entry is not sent again.
    var textHash: String
    var digestedAt: Date
    var model: String
    /// Two or three sentences on what the entry is about.
    var summary: String
    /// The thoughts this entry touched.
    var thoughts: [String]
    var openLoops: [String]
    /// Items the app turned down, with reasons, so the result can be audited.
    var rejected: [Rejection]
    var inputTokens: Int?
    var outputTokens: Int?
    /// True when the model's answer could not be used at all. The entry is then
    /// left alone until its text changes or memory is rebuilt.
    var failed: Bool
    var failureReason: String?

    /// The names used in the JSON file.
    private enum CodingKeys: String, CodingKey {
        case entryID = "entry_id"
        case entryDate = "entry_date"
        case textHash = "text_hash"
        case digestedAt = "digested_at"
        case model
        case summary
        case thoughts
        case openLoops = "open_loops"
        case rejected
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case failed
        case failureReason = "failure_reason"
    }
}

/// The user's manual fixes, kept in memory/pins.json. The AI reads these and must obey them.
///
/// Each fix also records the names the thought went by at the time. After a
/// rebuild the AI may name a thought a little differently, so fixes are matched
/// by those names as well as by the note's file name.
struct Pins: Codable, Equatable {
    struct Rename: Codable, Equatable {
        var id: String
        /// The name the user gave it.
        var label: String
        /// What it was called before, and its other names.
        var names: [String]? = nil
    }

    struct Merge: Codable, Equatable {
        /// The thought that was folded away.
        var from: String
        /// The thought it now belongs to.
        var into: String
        /// What the folded thought was called, and its other names.
        var names: [String]? = nil
        /// What the thought it joined was called at the time.
        var intoLabel: String? = nil

        private enum CodingKeys: String, CodingKey {
            case from
            case into
            case names
            case intoLabel = "into_label"
        }
    }

    struct Deletion: Codable, Equatable {
        var id: String
        /// Kept so the same thought cannot come back under the same name.
        var label: String
        /// Its other names.
        var names: [String]? = nil
    }

    struct LinkPin: Codable, Equatable {
        var from: String
        var to: String
        var reason: String?
    }

    var renames: [Rename] = []
    var merges: [Merge] = []
    var deletions: [Deletion] = []
    var linksAdded: [LinkPin] = []
    var linksRemoved: [LinkPin] = []

    init() {}

    /// The names used in pins.json.
    private enum CodingKeys: String, CodingKey {
        case renames
        case merges
        case deletions
        case linksAdded = "links_added"
        case linksRemoved = "links_removed"
    }

    /// Any section may be left out of the file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        renames = try container.decodeIfPresent([Rename].self, forKey: .renames) ?? []
        merges = try container.decodeIfPresent([Merge].self, forKey: .merges) ?? []
        deletions = try container.decodeIfPresent([Deletion].self, forKey: .deletions) ?? []
        linksAdded = try container.decodeIfPresent([LinkPin].self, forKey: .linksAdded) ?? []
        linksRemoved = try container.decodeIfPresent([LinkPin].self, forKey: .linksRemoved) ?? []
    }

    var isEmpty: Bool {
        renames.isEmpty && merges.isEmpty && deletions.isEmpty && linksAdded.isEmpty && linksRemoved.isEmpty
    }

    /// Follows merges to the thought an id now belongs to.
    func resolve(_ id: String) -> String {
        var current = id
        var visited: Set<String> = [id]
        while let merge = merges.first(where: { $0.from == current }), !visited.contains(merge.into) {
            current = merge.into
            visited.insert(current)
        }
        return current
    }

    func isDeleted(_ id: String) -> Bool {
        deletions.contains { $0.id == id }
    }

    /// True if the user deleted a thought that went by this name.
    func hasDeleted(name: String) -> Bool {
        let wanted = MemoryText.normalizedName(name)
        guard !wanted.isEmpty else { return false }
        return deletions.contains { deletion in
            ([deletion.label, deletion.id] + (deletion.names ?? [])).contains { MemoryText.normalizedName($0) == wanted }
        }
    }

    /// The label the user chose for a thought, if they renamed it.
    func pinnedLabel(for id: String) -> String? {
        renames.last { $0.id == id }?.label
    }

    /// True if the user has renamed this thought or linked it by hand.
    /// The weekly tidy leaves such thoughts alone.
    func isTouchedByUser(_ id: String) -> Bool {
        renames.contains { $0.id == id } || linksAdded.contains { $0.from == id || $0.to == id }
    }

    /// The thought a name belongs to according to the user's fixes: one they
    /// renamed (by its new or old names) or one they folded into another.
    /// Used after a rebuild, when the AI's own names may have shifted.
    func pinnedID(forName name: String) -> String? {
        let wanted = MemoryText.normalizedName(name)
        guard !wanted.isEmpty else { return nil }
        for rename in renames {
            if ([rename.label, rename.id] + (rename.names ?? [])).contains(where: { MemoryText.normalizedName($0) == wanted }) {
                return resolve(rename.id)
            }
        }
        for merge in merges {
            if ([merge.from] + (merge.names ?? [])).contains(where: { MemoryText.normalizedName($0) == wanted }) {
                return resolve(merge.into)
            }
        }
        return nil
    }

    /// The label to give a thought created under a merge target that does not exist yet.
    func mergeTargetLabel(for id: String) -> String? {
        merges.last { $0.into == id && $0.intoLabel != nil }?.intoLabel
    }

    /// True if the user removed the link between these two thoughts, in either direction.
    func isLinkRemoved(_ first: String, _ second: String) -> Bool {
        linksRemoved.contains {
            ($0.from == first && $0.to == second) || ($0.from == second && $0.to == first)
        }
    }
}

/// Small text helpers shared across memory.
enum MemoryText {
    /// Lower-cased, accents removed, punctuation and extra spaces dropped.
    /// Two names that normalise to the same text are treated as the same thought.
    static func normalizedName(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if scalar == "'" || scalar == "\u{2019}" || scalar == "\u{2018}" {
                // "can't" and "cant" are the same name.
                continue
            }
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// A file-name-safe id made from a label: "Saying yes, under pressure!" becomes "saying-yes-under-pressure".
    static func slug(_ text: String) -> String {
        let words = normalizedName(text)
            .unicodeScalars
            .map { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains($0) ? Character($0) : " " }
        let slug = String(words)
            .split(separator: " ")
            .joined(separator: "-")
        let trimmed = String(slug.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "thought" : trimmed
    }

    /// One line, with line breaks and repeated spaces collapsed.
    static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The day a date falls on, in the Mac's own time zone, as yyyy-MM-dd.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
