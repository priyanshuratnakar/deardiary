//
//  DigestResult.swift
//  Dear Diary
//
//  What the AI sends back after reading one entry, and the strict check that
//  it has exactly the expected shape before anything else looks at it.
//
//  Since M14 the reply is a plain list of what is in the entry, each item with
//  a line copied from it: people, topics, feelings in the writer's own words,
//  what happened, what they told themselves, what helped, what they want, and
//  what is still open. The AI names nothing and explains nothing. The app
//  decides what becomes a thought and what stays on the day (MemoryApplier).
//
//  The same shape is given to the model as a JSON schema, so the reply is
//  built to fit. It is still checked here, field by field, because a reply can
//  be cut short or declined, and because a model that does not support
//  schemas may be chosen in Settings.
//

import Foundation

struct DigestResult: Equatable {
    /// A person or a topic, by the name the writer uses.
    struct Named: Equatable {
        var name: String
        var quote: String
    }

    /// A feeling or body state the writer named about themselves.
    struct Feeling: Equatable {
        /// Their own word or short phrase for it.
        var word: String
        var tone: DayLine.Tone
        var quote: String
    }

    /// Something described in a few plain words, with the line behind it.
    struct Noted: Equatable {
        var what: String
        var quote: String
    }

    var people: [Named] = []
    var topics: [Named] = []
    var feelings: [Feeling] = []
    /// What happened, or what they did.
    var happened: [Noted] = []
    /// What they told themselves, realised or admitted. Only the line is kept.
    var selfTalk: [String] = []
    /// Something after which, by their own account, they felt better.
    var helped: [Noted] = []
    /// What they said they want, do not want, or have decided.
    var matters: [Noted] = []
    /// What they said they still need to do or decide.
    var openLoops: [Noted] = []
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
            "people", "topics", "feelings", "happened", "self_talk", "helped", "matters", "open_loops",
        ])

        func named(_ key: String) throws -> [DigestResult.Named] {
            try array(object, key).map { item in
                let fields = try dictionary(item, named: key, keys: ["name", "quote"])
                return DigestResult.Named(name: try string(fields, "name"), quote: try string(fields, "quote"))
            }
        }

        func noted(_ key: String) throws -> [DigestResult.Noted] {
            try array(object, key).map { item in
                let fields = try dictionary(item, named: key, keys: ["what", "quote"])
                return DigestResult.Noted(what: try string(fields, "what"), quote: try string(fields, "quote"))
            }
        }

        var result = DigestResult()
        result.people = try named("people")
        result.topics = try named("topics")

        result.feelings = try array(object, "feelings").map { item in
            let fields = try dictionary(item, named: "feelings", keys: ["word", "tone", "quote"])
            let tone = try string(fields, "tone").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let known = DayLine.Tone(rawValue: tone) else {
                throw DigestParseError(reason: "A feeling had a tone that is not pleasant, unpleasant or mixed.")
            }
            return DigestResult.Feeling(word: try string(fields, "word"), tone: known, quote: try string(fields, "quote"))
        }

        result.happened = try noted("happened")
        result.selfTalk = try array(object, "self_talk").map { item in
            try string(try dictionary(item, named: "self_talk", keys: ["quote"]), "quote")
        }
        result.helped = try noted("helped")
        result.matters = try noted("matters")
        result.openLoops = try noted("open_loops")
        return result
    }

    // MARK: - Strict readers

    /// A model without schema support may wrap its JSON in a ``` block. Nothing else is tolerated.
    static func stripCodeFence(_ text: String) -> String {
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
    static func dictionary(_ value: Any, named name: String, keys: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw DigestParseError(reason: "\(name) was not an object.")
        }
        guard Set(object.keys) == keys else {
            throw DigestParseError(reason: "\(name) did not have exactly the expected fields.")
        }
        return object
    }

    static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw DigestParseError(reason: "\(key) was not text.")
        }
        return value
    }

    static func optionalString(_ object: [String: Any], _ key: String) throws -> String? {
        if object[key] is NSNull {
            return nil
        }
        return try string(object, key)
    }

    static func array(_ object: [String: Any], _ key: String) throws -> [Any] {
        guard let value = object[key] as? [Any] else {
            throw DigestParseError(reason: "\(key) was not a list.")
        }
        return value
    }

    static func strings(_ object: [String: Any], _ key: String) throws -> [String] {
        guard let value = object[key] as? [String] else {
            throw DigestParseError(reason: "\(key) was not a list of text.")
        }
        return value
    }
}

/// The shape of a digest, as a JSON schema. Every object lists all of its fields and
/// allows no others, as the services require. It is written in the order a reply is best
/// filled in (see rule 11 of M8: the shape is sent exactly as written).
/// It must stay in step with `DigestParser` above; a test checks that it does.
enum DigestSchema {
    static let json = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "people",
        "topics",
        "feelings",
        "happened",
        "self_talk",
        "helped",
        "matters",
        "open_loops"
      ],
      "properties": {
        "people": {
          "type": "array",
          "description": "Every person named or referred to in the entry.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "name",
              "quote"
            ],
            "properties": {
              "name": {
                "type": "string",
                "description": "How the writer refers to them. If they are already in memory, that exact name."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "topics": {
          "type": "array",
          "description": "Things the entry is about that could come up again.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "name",
              "quote"
            ],
            "properties": {
              "name": {
                "type": "string",
                "description": "Two or three plain words from the entry. If it is already in memory, that exact name."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "feelings": {
          "type": "array",
          "description": "Feelings or body states the writer names about themselves.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "word",
              "tone",
              "quote"
            ],
            "properties": {
              "word": {
                "type": "string",
                "description": "Their own word or short phrase for it."
              },
              "tone": {
                "type": "string",
                "enum": [
                  "pleasant",
                  "unpleasant",
                  "mixed"
                ]
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "happened": {
          "type": "array",
          "description": "Things that happened or that they did.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "what",
              "quote"
            ],
            "properties": {
              "what": {
                "type": "string",
                "description": "A short plain phrase."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "self_talk": {
          "type": "array",
          "description": "What they tell themselves, realise or admit about themselves.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "quote"
            ],
            "properties": {
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "helped": {
          "type": "array",
          "description": "Something after which, by their own account, they felt better.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "what",
              "quote"
            ],
            "properties": {
              "what": {
                "type": "string",
                "description": "The thing that helped, in a few plain words."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        },
        "matters": {
          "type": "array",
          "description": "What they say they want, do not want, or have decided.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "what",
              "quote"
            ],
            "properties": {
              "what": {
                "type": "string",
                "description": "A short plain phrase."
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
          "description": "Things they say they still need to do or decide.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "what",
              "quote"
            ],
            "properties": {
              "what": {
                "type": "string",
                "description": "A short plain phrase."
              },
              "quote": {
                "type": "string",
                "description": "A line copied exactly from this entry."
              }
            }
          }
        }
      }
    }
    """

    /// The schema as JSON bytes, ready to attach to a request.
    static let data = Data(json.utf8)
}
