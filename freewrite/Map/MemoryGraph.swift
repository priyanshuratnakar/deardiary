//
//  MemoryGraph.swift
//  Dear Diary
//
//  The map's picture of memory: dots and thin lines.
//
//  There are two kinds of dot. A thought is a coloured dot, bigger the more
//  entries touch it. A day is a small grey dot, one for each entry that memory
//  has read, joined to every thought that entry touched. Thoughts are also
//  joined to each other where the AI or the user has linked them.
//
//  It is built fresh from the thought notes every time the map opens, so the
//  notes stay the single source of truth. Only the positions are remembered,
//  in memory/graph.json, so a dot stays where it was left.
//

import Foundation
import SwiftUI

/// One dot on the map: a thought, or a day.
struct GraphNode: Equatable, Identifiable {
    /// A thought's id, or "day:" and the entry's id for a day.
    let id: String
    /// A thought's name, or the day written out in full.
    var label: String
    /// The kind of thought. Nil for a day.
    var kind: ThoughtKind?
    /// For a thought, how many different entries touched it (this decides its size).
    /// For a day, how many thoughts it touched.
    var weight: Int
    /// Where the dot sits, in the map's own coordinates (the middle of the map is zero).
    var position: CGPoint
    /// For a day: the entry written that day.
    var entryID: UUID? = nil
    /// For a day: the date, as yyyy-MM-dd.
    var date: String? = nil

    var isDay: Bool { entryID != nil }

    static func dayID(_ entryID: UUID) -> String {
        "day:\(entryID.uuidString)"
    }

    /// The size of the dot. A thought grows with how often it recurs, gently, up to a limit.
    /// A day is always small.
    var radius: CGFloat {
        isDay ? 2.8 : min(22, 2.6 + 2.6 * CGFloat(Double(max(weight, 1)).squareRoot()))
    }
}

/// A line between two thoughts. However many entries show the link, it is one line.
struct GraphEdge: Equatable, Identifiable {
    /// The two thought ids in alphabetical order, joined by "|".
    let id: String
    let first: String
    let second: String
    /// How many separate lines of evidence there are for this link.
    var count: Int
    /// The reasons given, without repeats.
    var reasons: [String]
    /// True for the line between a day and a thought it touched.
    var isDayLink = false

    static func id(_ one: String, _ other: String) -> String {
        one < other ? "\(one)|\(other)" : "\(other)|\(one)"
    }
}

struct MemoryGraph: Equatable {
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []

    var isEmpty: Bool { nodes.isEmpty }

    var thoughts: [GraphNode] { nodes.filter { !$0.isDay } }
    var days: [GraphNode] { nodes.filter(\.isDay) }

    /// For each thought, the thoughts it is linked to.
    var neighbours: [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for edge in edges {
            result[edge.first, default: []].insert(edge.second)
            result[edge.second, default: []].insert(edge.first)
        }
        return result
    }
}

enum GraphBuilder {
    /// Builds the graph from the thought notes.
    /// - Parameter saved: positions remembered from last time, by thought id.
    /// - Returns: the graph, and the thoughts that have no remembered position yet.
    static func build(from memory: MemorySnapshot, saved: [String: CGPoint]) -> (graph: MemoryGraph, unplaced: Set<String>) {
        var unplaced: Set<String> = []

        var nodes = memory.thoughts.values
            .sorted { $0.id < $1.id }
            .map { thought -> GraphNode in
                if saved[thought.id] == nil {
                    unplaced.insert(thought.id)
                }
                return GraphNode(
                    id: thought.id,
                    label: thought.label,
                    kind: thought.kind,
                    weight: Set(thought.evidence.map(\.entryID)).count,
                    position: saved[thought.id] ?? .zero
                )
            }

        var edges: [String: GraphEdge] = [:]
        for thought in memory.thoughts.values.sorted(by: { $0.id < $1.id }) {
            for link in thought.links.sorted(by: { ($0.target, $0.date, $0.reason) < ($1.target, $1.date, $1.reason) }) {
                // A link to a thought that is no longer there is not drawn.
                guard link.target != thought.id, memory.thoughts[link.target] != nil else { continue }
                let id = GraphEdge.id(thought.id, link.target)
                var edge = edges[id] ?? GraphEdge(
                    id: id,
                    first: min(thought.id, link.target),
                    second: max(thought.id, link.target),
                    count: 0,
                    reasons: []
                )
                edge.count += 1
                if !edge.reasons.contains(link.reason) {
                    edge.reasons.append(link.reason)
                }
                edges[id] = edge
            }

            // Links the user made by hand.
            for link in thought.userLinks.sorted(by: { ($0.target, $0.reason) < ($1.target, $1.reason) }) {
                guard link.target != thought.id, memory.thoughts[link.target] != nil else { continue }
                let id = GraphEdge.id(thought.id, link.target)
                var edge = edges[id] ?? GraphEdge(
                    id: id,
                    first: min(thought.id, link.target),
                    second: max(thought.id, link.target),
                    count: 0,
                    reasons: []
                )
                edge.count += 1
                if !link.reason.isEmpty, !edge.reasons.contains(link.reason) {
                    edge.reasons.append(link.reason)
                }
                edges[id] = edge
            }
        }

        // Days: one small dot for each entry memory has read, joined to the thoughts it touched.
        var touchedBy: [UUID: (date: String, thoughts: Set<String>)] = [:]
        for thought in memory.thoughts.values {
            for item in thought.evidence {
                var day = touchedBy[item.entryID] ?? (item.date, [])
                // One entry has one date. If notes ever disagree, the earliest is used,
                // so the picture never depends on the order the notes were read in.
                day.date = min(day.date, item.date)
                day.thoughts.insert(thought.id)
                touchedBy[item.entryID] = day
            }
        }
        for (entryID, day) in touchedBy.sorted(by: { ($0.value.date, $0.key.uuidString) < ($1.value.date, $1.key.uuidString) }) {
            let id = GraphNode.dayID(entryID)
            if saved[id] == nil {
                unplaced.insert(id)
            }
            nodes.append(GraphNode(
                id: id,
                label: Prompts.longDay(day.date),
                kind: nil,
                weight: day.thoughts.count,
                position: saved[id] ?? .zero,
                entryID: entryID,
                date: day.date
            ))
            for thoughtID in day.thoughts.sorted() {
                let edgeID = GraphEdge.id(id, thoughtID)
                edges[edgeID] = GraphEdge(
                    id: edgeID,
                    first: min(id, thoughtID),
                    second: max(id, thoughtID),
                    count: 1,
                    reasons: [],
                    isDayLink: true
                )
            }
        }

        let graph = MemoryGraph(nodes: nodes, edges: edges.values.sorted { $0.id < $1.id })
        return (graph, unplaced)
    }
}

// MARK: - memory/graph.json

/// The file the map keeps: the graph as it was last drawn, with where each dot sits.
/// Only the positions are read back; everything else is rebuilt from the thought notes.
struct GraphFile: Codable, Equatable {
    struct Node: Codable, Equatable {
        var id: String
        var label: String
        var kind: String
        var weight: Int
        var x: Double
        var y: Double
    }

    struct Edge: Codable, Equatable {
        var from: String
        var to: String
        var count: Int
        var reasons: [String]
    }

    var version = 1
    var nodes: [Node] = []
    var edges: [Edge] = []
}

extension MemoryStore {
    var graphURL: URL { folder.appendingPathComponent("graph.json") }

    /// Where each dot was left, by thought id. Empty if the file is missing or unreadable.
    func loadGraphPositions() -> [String: CGPoint] {
        guard let data = try? Data(contentsOf: graphURL),
              let file = try? JSONDecoder().decode(GraphFile.self, from: data) else {
            return [:]
        }
        var positions: [String: CGPoint] = [:]
        for node in file.nodes where node.x.isFinite && node.y.isFinite {
            positions[node.id] = CGPoint(x: node.x, y: node.y)
        }
        return positions
    }

    func saveGraph(_ graph: MemoryGraph) throws {
        let file = GraphFile(
            nodes: graph.nodes.map {
                GraphFile.Node(
                    id: $0.id,
                    label: $0.label,
                    kind: $0.kind?.rawValue ?? "day",
                    weight: $0.weight,
                    x: (Double($0.position.x) * 10).rounded() / 10,
                    y: (Double($0.position.y) * 10).rounded() / 10
                )
            },
            edges: graph.edges.map {
                GraphFile.Edge(from: $0.first, to: $0.second, count: $0.count, reasons: $0.reasons)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(file).write(to: graphURL, options: .atomic)
    }
}

// MARK: - Colour by kind

/// The colour of a dot, by the kind of thought. These seven are the only
/// colours in the app; text on the map stays grey or black.
///
/// The values are a tested set: each pair of neighbours in the list can be told
/// apart, including with the common forms of colour blindness, and each is
/// stepped separately for the white and the black background. Seven scattered
/// colours cannot all be told apart by everyone, so the kind is always written
/// in words as well: in the legend, on hover, and in the detail panel.
enum MapPalette {
    static func color(for kind: ThoughtKind, isLight: Bool) -> Color {
        Color(hex: isLight ? light[kind] ?? 0x808080 : dark[kind] ?? 0x808080)
    }

    private static let light: [ThoughtKind: UInt32] = [
        .theme: 0x2A78D6,
        .feeling: 0xEB6834,
        .person: 0x1BAF7A,
        .idea: 0xEDA100,
        .question: 0xE87BA4,
        .decision: 0x008300,
        .event: 0x6250D6,
    ]

    private static let dark: [ThoughtKind: UInt32] = [
        .theme: 0x3987E5,
        .feeling: 0xD95926,
        .person: 0x199E70,
        .idea: 0xC98500,
        .question: 0xD55181,
        .decision: 0x008300,
        .event: 0x9085E9,
    ]
}

extension Color {
    /// A colour from a number such as 0x2A78D6.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
