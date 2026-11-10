//
//  MemoryGraph.swift
//  Dear Diary
//
//  The map's picture of memory: thoughts as dots and links as lines.
//
//  It is built fresh from the thought notes every time the map opens, so the
//  notes stay the single source of truth. Only the positions are remembered,
//  in memory/graph.json, so a dot stays where it was left.
//

import Foundation
import SwiftUI

/// One thought on the map.
struct GraphNode: Equatable, Identifiable {
    let id: String
    var label: String
    var kind: ThoughtKind
    /// How many different entries touched this thought. Decides the size of the dot.
    var weight: Int
    /// Where the dot sits, in the map's own coordinates (the middle of the map is zero).
    var position: CGPoint

    /// The size of the dot. It grows with how often the thought recurs, gently, up to a limit.
    var radius: CGFloat {
        min(20, 5 + 2.5 * CGFloat(Double(max(weight, 1)).squareRoot()))
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

    static func id(_ one: String, _ other: String) -> String {
        one < other ? "\(one)|\(other)" : "\(other)|\(one)"
    }
}

struct MemoryGraph: Equatable {
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []

    var isEmpty: Bool { nodes.isEmpty }

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

        let nodes = memory.thoughts.values
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
                    kind: $0.kind.rawValue,
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
