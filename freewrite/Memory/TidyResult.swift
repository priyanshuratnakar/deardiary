//
//  TidyResult.swift
//  Dear Diary
//
//  What the AI sends back from the weekly tidy, and the strict check that it
//  has exactly the expected shape before anything else looks at it.
//
//  A digest reads one entry. The tidy looks across all of memory: it can
//  propose merging two thoughts that are the same thing, and retiring ones
//  that came up once and never returned. Every proposal is checked by
//  MemoryTidier before it changes anything.
//

import Foundation

struct TidyResult: Equatable {
    /// Two thoughts that are the same thing: fold `from` into `into`.
    struct Merge: Equatable {
        var from: String
        var into: String
    }

    var merges: [Merge] = []
    /// Ids of thoughts proposed for retiring. The app decides whether each really is a one-off.
    var retire: [String] = []
}

enum TidyParser {
    /// Reads the AI's reply. Anything that is not exactly the expected shape is refused.
    static func parse(_ text: String) throws -> TidyResult {
        let json = DigestParser.stripCodeFence(text)
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            throw DigestParseError(reason: "The reply was not valid JSON.")
        }
        let object = try DigestParser.dictionary(root, named: "reply", keys: ["merges", "retire"])

        var result = TidyResult()
        result.merges = try DigestParser.array(object, "merges").map { item in
            let fields = try DigestParser.dictionary(item, named: "merges", keys: ["from", "into"])
            return TidyResult.Merge(from: try DigestParser.string(fields, "from"), into: try DigestParser.string(fields, "into"))
        }
        result.retire = try DigestParser.strings(object, "retire")
        return result
    }
}

/// The shape of a tidy, as a JSON schema.
/// It must stay in step with `TidyParser` above; a test checks that it does.
enum TidySchema {
    static let json = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "merges",
        "retire"
      ],
      "properties": {
        "merges": {
          "type": "array",
          "description": "Pairs of thoughts that are the same thing under two names.",
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
                "description": "The id of the less established thought, which is folded away."
              },
              "into": {
                "type": "string",
                "description": "The id of the thought it joins."
              }
            }
          }
        },
        "retire": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Ids of people and topics that came up in one entry some weeks ago and never returned."
        }
      }
    }
    """

    /// The schema as JSON bytes, ready to attach to a request.
    static let data = Data(json.utf8)
}
