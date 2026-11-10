//
//  DigestResult.swift
//  Dear Diary
//
//  What the AI sends back after reading one entry, and the strict check that
//  it has exactly the expected shape before anything else looks at it.
//
//  The same shape is given to Claude as a JSON schema, so the reply is built
//  to fit. It is still checked here, field by field, because a reply can be
//  cut short or declined, and because a model that does not support schemas
//  may be chosen in Settings.
//

import Foundation

struct DigestResult: Equatable {
    /// More evidence for a thought that already exists.
    struct ThoughtUpdate: Equatable {
        var thoughtID: String
        var quote: String
        /// A revised "what this is", or nil to leave it.
        var newSummary: String?
        /// Another name the thought went by in this entry, or nil.
        var newAlias: String?
    }

    /// A thought that is not in memory yet.
    struct NewThought: Equatable {
        var label: String
        var kind: ThoughtKind
        var summary: String
        var aliases: [String]
        var quote: String
    }

    /// A connection between two thoughts, with a reason.
    struct Link: Equatable {
        /// An existing thought's id, or the label of a thought created in this reply.
        var from: String
        var to: String
        var reason: String
        var quote: String
    }

    /// A note on how a thought shifted in this entry.
    struct TimelineEntry: Equatable {
        var thought: String
        var note: String
        var quote: String
    }

    /// Two or three sentences on what the entry is about.
    var summary: String
    var thoughtUpdates: [ThoughtUpdate] = []
    var newThoughts: [NewThought] = []
    var links: [Link] = []
    var timelineNotes: [TimelineEntry] = []
    var openLoops: [String] = []
    /// The whole profile, rewritten, or nil to leave it as it is.
    var profile: String? = nil
}

/// Why a reply could not be used. The reasons never contain entry text.
struct DigestParseError: Error, Equatable {
    let reason: String
}

enum DigestParser {
    /// Reads the AI's reply. Anything that is not exactly the expected shape is refused.
    static func parse(_ text: String) throws -> DigestResult {
        let json = stripCodeFence(text)
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            throw DigestParseError(reason: "The reply was not valid JSON.")
        }
        let object = try dictionary(root, named: "reply", keys: [
            "summary", "thought_updates", "new_thoughts", "links", "timeline_notes", "open_loops", "profile",
        ])

        var result = DigestResult(summary: try string(object, "summary"))

        result.thoughtUpdates = try array(object, "thought_updates").map { item in
            let fields = try dictionary(item, named: "thought_updates", keys: ["thought_id", "quote", "new_summary", "new_alias"])
            return DigestResult.ThoughtUpdate(
                thoughtID: try string(fields, "thought_id"),
                quote: try string(fields, "quote"),
                newSummary: try optionalString(fields, "new_summary"),
                newAlias: try optionalString(fields, "new_alias")
            )
        }

        result.newThoughts = try array(object, "new_thoughts").map { item in
            let fields = try dictionary(item, named: "new_thoughts", keys: ["label", "kind", "summary", "aliases", "quote"])
            guard let kind = ThoughtKind(loose: try string(fields, "kind")) else {
                throw DigestParseError(reason: "A new thought had a kind that is not one of the seven allowed.")
            }
            return DigestResult.NewThought(
                label: try string(fields, "label"),
                kind: kind,
                summary: try string(fields, "summary"),
                aliases: try strings(fields, "aliases"),
                quote: try string(fields, "quote")
            )
        }

        result.links = try array(object, "links").map { item in
            let fields = try dictionary(item, named: "links", keys: ["from", "to", "reason", "quote"])
            return DigestResult.Link(
                from: try string(fields, "from"),
                to: try string(fields, "to"),
                reason: try string(fields, "reason"),
                quote: try string(fields, "quote")
            )
        }

        result.timelineNotes = try array(object, "timeline_notes").map { item in
            let fields = try dictionary(item, named: "timeline_notes", keys: ["thought", "note", "quote"])
            return DigestResult.TimelineEntry(
                thought: try string(fields, "thought"),
                note: try string(fields, "note"),
                quote: try string(fields, "quote")
            )
        }

        result.openLoops = try strings(object, "open_loops")
        result.profile = try optionalString(object, "profile")
        return result
    }

    // MARK: - Strict readers

    /// A model without schema support may wrap its JSON in a ``` block. Nothing else is tolerated.
    private static func stripCodeFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.count >= 6 else {
            return trimmed
        }
        trimmed = String(trimmed.dropFirst(3).dropLast(3))
        if let newline = trimmed.firstIndex(of: "\n"), !trimmed[..<newline].contains("{") {
            trimmed = String(trimmed[trimmed.index(after: newline)...])
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An object with exactly these keys: none missing, none extra.
    private static func dictionary(_ value: Any, named name: String, keys: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw DigestParseError(reason: "\(name) was not an object.")
        }
        guard Set(object.keys) == keys else {
            throw DigestParseError(reason: "\(name) did not have exactly the expected fields.")
        }
        return object
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw DigestParseError(reason: "\(key) was not text.")
        }
        return value
    }

    private static func optionalString(_ object: [String: Any], _ key: String) throws -> String? {
        if object[key] is NSNull {
            return nil
        }
        return try string(object, key)
    }

    private static func array(_ object: [String: Any], _ key: String) throws -> [Any] {
        guard let value = object[key] as? [Any] else {
            throw DigestParseError(reason: "\(key) was not a list.")
        }
        return value
    }

    private static func strings(_ object: [String: Any], _ key: String) throws -> [String] {
        guard let value = object[key] as? [String] else {
            throw DigestParseError(reason: "\(key) was not a list of text.")
        }
        return value
    }
}

/// The shape of a digest, in the form Claude's API takes (a JSON schema).
/// Every object lists all of its fields and allows no others, as the API requires.
/// It must stay in step with `DigestParser` above; a test checks that it does.
enum DigestSchema {
    static let json = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "summary",
        "thought_updates",
        "new_thoughts",
        "links",
        "timeline_notes",
        "open_loops",
        "profile"
      ],
      "properties": {
        "summary": {
          "type": "string",
          "description": "Two or three sentences on what this entry is about."
        },
        "thought_updates": {
          "type": "array",
          "description": "Thoughts from the index that this entry touches.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "thought_id",
              "quote",
              "new_summary",
              "new_alias"
            ],
            "properties": {
              "thought_id": {
                "type": "string",
                "description": "An id copied exactly from the index."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              },
              "new_summary": {
                "type": [
                  "string",
                  "null"
                ],
                "description": "A revised one or two sentence description, or null to keep the current one."
              },
              "new_alias": {
                "type": [
                  "string",
                  "null"
                ],
                "description": "Another name used for it in this entry, or null."
              }
            }
          }
        },
        "new_thoughts": {
          "type": "array",
          "description": "Thoughts that are not in the index. Create one only when nothing in the index fits.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "label",
              "kind",
              "summary",
              "aliases",
              "quote"
            ],
            "properties": {
              "label": {
                "type": "string",
                "description": "A short plain name, two to five words."
              },
              "kind": {
                "type": "string",
                "enum": [
                  "theme",
                  "feeling",
                  "person",
                  "idea",
                  "question",
                  "decision",
                  "event"
                ]
              },
              "summary": {
                "type": "string",
                "description": "One or two sentences on what this is."
              },
              "aliases": {
                "type": "array",
                "items": {
                  "type": "string"
                },
                "description": "Other names it went by in this entry. May be empty."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "links": {
          "type": "array",
          "description": "Connections between two thoughts that this entry shows.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "from",
              "to",
              "reason",
              "quote"
            ],
            "properties": {
              "from": {
                "type": "string",
                "description": "An id from the index, or the exact label of a new thought in this reply."
              },
              "to": {
                "type": "string",
                "description": "An id from the index, or the exact label of a new thought in this reply."
              },
              "reason": {
                "type": "string",
                "description": "A few plain words, such as: shows up whenever, in tension with, led to."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "timeline_notes": {
          "type": "array",
          "description": "Notes on how a thought shifted in this entry.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "thought",
              "note",
              "quote"
            ],
            "properties": {
              "thought": {
                "type": "string",
                "description": "An id from the index, or the exact label of a new thought in this reply."
              },
              "note": {
                "type": "string",
                "description": "One short sentence on what changed."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "open_loops": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Things they said they need to do, decide or come back to."
        },
        "profile": {
          "type": [
            "string",
            "null"
          ],
          "description": "The whole profile rewritten, or null if this entry does not change the picture."
        }
      }
    }
    """

    /// The schema as JSON bytes, ready to attach to a request.
    static let data = Data(json.utf8)
}
