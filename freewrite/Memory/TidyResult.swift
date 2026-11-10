//
//  TidyResult.swift
//  Dear Diary
//
//  What the AI sends back from the weekly tidy, and the strict check that it
//  has exactly the expected shape before anything else looks at it.
//
//  A digest reads one entry. The tidy looks across all of memory: it can
//  propose merging duplicates, retiring one-offs, patterns that only show
//  across several entries, and a refreshed profile. Every proposal is checked
//  by MemoryTidier before it changes anything.
//

import Foundation

struct TidyResult: Equatable {
    /// Two thoughts that are the same thing: fold `from` into `into`.
    struct Merge: Equatable {
        var from: String
        var into: String
    }

    /// A quoted line and the entry it is said to come from.
    struct Quote: Equatable {
        var entryID: String
        var quote: String
    }

    /// Something that recurs across entries and deserves its own thought.
    struct Pattern: Equatable {
        var label: String
        var kind: ThoughtKind
        var summary: String
        var evidence: [Quote]
    }

    /// A relationship between two thoughts that shows across entries.
    struct Link: Equatable {
        var from: String
        var to: String
        var reason: String
        var evidence: [Quote]
    }

    var merges: [Merge] = []
    /// Ids of thoughts proposed for retiring. The app decides whether each really is a one-off.
    var retire: [String] = []
    var patterns: [Pattern] = []
    var links: [Link] = []
    /// The whole profile, rewritten, or nil to leave it as it is.
    var profile: String? = nil
}

enum TidyParser {
    /// Reads the AI's reply. Anything that is not exactly the expected shape is refused.
    static func parse(_ text: String) throws -> TidyResult {
        let json = DigestParser.stripCodeFence(text)
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            throw DigestParseError(reason: "The reply was not valid JSON.")
        }
        let object = try DigestParser.dictionary(root, named: "reply", keys: ["merges", "retire", "patterns", "links", "profile"])

        var result = TidyResult()

        result.merges = try DigestParser.array(object, "merges").map { item in
            let fields = try DigestParser.dictionary(item, named: "merges", keys: ["from", "into"])
            return TidyResult.Merge(from: try DigestParser.string(fields, "from"), into: try DigestParser.string(fields, "into"))
        }

        result.retire = try DigestParser.strings(object, "retire")

        result.patterns = try DigestParser.array(object, "patterns").map { item in
            let fields = try DigestParser.dictionary(item, named: "patterns", keys: ["label", "kind", "summary", "evidence"])
            guard let kind = ThoughtKind(loose: try DigestParser.string(fields, "kind")) else {
                throw DigestParseError(reason: "A pattern had a kind that is not one of the seven allowed.")
            }
            return TidyResult.Pattern(
                label: try DigestParser.string(fields, "label"),
                kind: kind,
                summary: try DigestParser.string(fields, "summary"),
                evidence: try quotes(fields)
            )
        }

        result.links = try DigestParser.array(object, "links").map { item in
            let fields = try DigestParser.dictionary(item, named: "links", keys: ["from", "to", "reason", "evidence"])
            return TidyResult.Link(
                from: try DigestParser.string(fields, "from"),
                to: try DigestParser.string(fields, "to"),
                reason: try DigestParser.string(fields, "reason"),
                evidence: try quotes(fields)
            )
        }

        result.profile = try DigestParser.optionalString(object, "profile")
        return result
    }

    private static func quotes(_ fields: [String: Any]) throws -> [TidyResult.Quote] {
        try DigestParser.array(fields, "evidence").map { item in
            let quote = try DigestParser.dictionary(item, named: "evidence", keys: ["entry_id", "quote"])
            return TidyResult.Quote(entryID: try DigestParser.string(quote, "entry_id"), quote: try DigestParser.string(quote, "quote"))
        }
    }
}

/// The shape of a tidy, in the form Claude's API takes (a JSON schema).
/// It must stay in step with `TidyParser` above; a test checks that it does.
enum TidySchema {
    static let json = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "merges",
        "retire",
        "patterns",
        "links",
        "profile"
      ],
      "properties": {
        "merges": {
          "type": "array",
          "description": "Thoughts that are clearly the same thing under different names.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "from",
              "into"
            ],
            "properties": {
              "from": {
                "type": "string",
                "description": "The id of the thought to fold away."
              },
              "into": {
                "type": "string",
                "description": "The id of the thought it belongs to."
              }
            }
          }
        },
        "retire": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Ids of thoughts that came up once, weeks ago, and never returned."
        },
        "patterns": {
          "type": "array",
          "description": "Something that recurs across several entries and deserves its own thought.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "label",
              "kind",
              "summary",
              "evidence"
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
              "evidence": {
                "type": "array",
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": [
                    "entry_id",
                    "quote"
                  ],
                  "properties": {
                    "entry_id": {
                      "type": "string",
                      "description": "The id of the entry the line came from, copied exactly."
                    },
                    "quote": {
                      "type": "string",
                      "description": "A quoted line copied exactly as it was given."
                    }
                  }
                },
                "description": "Quoted lines from at least two different entries."
              }
            }
          }
        },
        "links": {
          "type": "array",
          "description": "A relationship between two thoughts that shows across several entries.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "from",
              "to",
              "reason",
              "evidence"
            ],
            "properties": {
              "from": {
                "type": "string",
                "description": "A thought id, or the exact label of a pattern in this reply."
              },
              "to": {
                "type": "string",
                "description": "A thought id, or the exact label of a pattern in this reply."
              },
              "reason": {
                "type": "string",
                "description": "A few plain words, such as: shows up whenever, in tension with, led to."
              },
              "evidence": {
                "type": "array",
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": [
                    "entry_id",
                    "quote"
                  ],
                  "properties": {
                    "entry_id": {
                      "type": "string",
                      "description": "The id of the entry the line came from, copied exactly."
                    },
                    "quote": {
                      "type": "string",
                      "description": "A quoted line copied exactly as it was given."
                    }
                  }
                },
                "description": "Quoted lines from at least two different entries."
              }
            }
          }
        },
        "profile": {
          "type": [
            "string",
            "null"
          ],
          "description": "The whole profile rewritten, or null if it still matches memory."
        }
      }
    }
    """

    /// The schema as JSON bytes, ready to attach to a request.
    static let data = Data(json.utf8)
}
