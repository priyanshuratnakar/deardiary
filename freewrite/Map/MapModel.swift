//
//  MapModel.swift
//  Dear Diary
//
//  What the map knows and can do: loading memory, placing the dots, panning
//  and zooming, working out what is under the pointer, moving a dot and
//  remembering where it was left, and preparing what the detail panel shows.
//
//  Reading the memory folder and working out the layout happen off the main
//  thread, so opening the map never holds up the app.
//

import Foundation
import SwiftUI
import AppKit

/// What is selected on the map.
enum MapSelection: Equatable {
    case thought(String)
    case link(String)
}

/// The lines quoted from one entry, for the detail panel.
struct MapDayQuotes: Equatable, Identifiable {
    let entryID: UUID
    /// The day the entry was started, as yyyy-MM-dd.
    let date: String
    let quotes: [String]

    var id: UUID { entryID }
}

/// What the panel shows for a thought.
struct MapThoughtDetail: Equatable {
    struct Shift: Equatable {
        let date: String
        let note: String
    }

    struct Connection: Equatable, Identifiable {
        let thoughtID: String
        let label: String
        let reasons: [String]
        let linkID: String

        var id: String { linkID }
    }

    let id: String
    let label: String
    let kind: ThoughtKind
    let aliases: [String]
    let summary: String
    let firstSeen: String?
    let lastSeen: String?
    let shifts: [Shift]
    let days: [MapDayQuotes]
    let connections: [Connection]
}

/// What the panel shows for a link between two thoughts.
struct MapLinkDetail: Equatable {
    let id: String
    let firstID: String
    let firstLabel: String
    let secondID: String
    let secondLabel: String
    let reasons: [String]
    let days: [MapDayQuotes]
}

@MainActor
final class MapModel: ObservableObject {
    @Published private(set) var graph = MemoryGraph()
    @Published private(set) var isLoading = true
    @Published var selection: MapSelection? = nil
    @Published var hoveredThought: String? = nil
    /// Set while the pointer is over a kind in the legend: only that kind stands out.
    @Published var highlightedKind: ThoughtKind? = nil
    /// How far the map has been dragged, in points on screen.
    @Published var pan: CGSize = .zero
    @Published var zoom: CGFloat = 1

    private(set) var memory = MemorySnapshot()
    private let store: MemoryStore
    private var neighbours: [String: Set<String>] = [:]
    private var draggedThought: String? = nil
    private var panAtDragStart: CGSize = .zero
    private var zoomAtPinchStart: CGFloat = 1
    private var scrollMonitor: Any? = nil
    /// True while the pointer is over the map itself (not the panel), so scrolling moves the map.
    var pointerIsOverMap = false

    static let zoomRange: ClosedRange<CGFloat> = 0.25...4

    init(store: MemoryStore = MemoryStore()) {
        self.store = store
    }

    // MARK: - Loading

    /// Reads the thought notes, places any thoughts that have no remembered position, and saves the result.
    func load() async {
        let store = self.store
        let loaded = await Task.detached(priority: .userInitiated) { () -> (MemorySnapshot, MemoryGraph) in
            let memory = store.loadSnapshot()
            let built = GraphBuilder.build(from: memory, saved: store.loadGraphPositions())
            let settled = GraphLayout.settle(built.graph, moving: built.unplaced)
            if !built.unplaced.isEmpty {
                try? store.saveGraph(settled)
            }
            return (memory, settled)
        }.value

        memory = loaded.0
        graph = loaded.1
        neighbours = graph.neighbours
        isLoading = false

        // A selection that no longer exists is dropped.
        switch selection {
        case .thought(let id) where memory.thoughts[id] == nil:
            selection = nil
        case .link(let id) where !graph.edges.contains(where: { $0.id == id }):
            selection = nil
        default:
            break
        }
    }

    /// For tests and pictures: show this memory without touching any files.
    func show(memory: MemorySnapshot, positions: [String: CGPoint] = [:]) {
        let built = GraphBuilder.build(from: memory, saved: positions)
        self.memory = memory
        graph = GraphLayout.settle(built.graph, moving: built.unplaced)
        neighbours = graph.neighbours
        isLoading = false
    }

    // MARK: - Screen and map coordinates

    func screenPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + pan.width + point.x * zoom,
            y: size.height / 2 + pan.height + point.y * zoom
        )
    }

    func mapPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - size.width / 2 - pan.width) / zoom,
            y: (point.y - size.height / 2 - pan.height) / zoom
        )
    }

    /// The size a dot is drawn at. Dots shrink with the map when zooming out, so a
    /// crowded map stays readable, and grow only a little when zooming in.
    func screenRadius(_ node: GraphNode) -> CGFloat {
        max(3, node.radius * min(zoom, 1.6))
    }

    /// Scales and centres the map so every dot is in view.
    func fit(in size: CGSize) {
        guard let first = graph.nodes.first, size.width > 0, size.height > 0 else {
            pan = .zero
            zoom = 1
            return
        }
        var minX = first.position.x, maxX = first.position.x
        var minY = first.position.y, maxY = first.position.y
        for node in graph.nodes {
            minX = min(minX, node.position.x - node.radius)
            maxX = max(maxX, node.position.x + node.radius)
            minY = min(minY, node.position.y - node.radius)
            maxY = max(maxY, node.position.y + node.radius)
        }
        let margin: CGFloat = 90
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        let scale = min((size.width - margin * 2) / width, (size.height - margin * 2) / height)
        zoom = min(max(scale, Self.zoomRange.lowerBound), 1.4)
        pan = CGSize(width: -(minX + maxX) / 2 * zoom, height: -(minY + maxY) / 2 * zoom)
    }

    // MARK: - What is under the pointer

    /// The thought at a point on screen, if any. The target is a little bigger than the dot.
    func thought(at point: CGPoint, in size: CGSize) -> String? {
        var best: (id: String, distance: CGFloat)? = nil
        for node in graph.nodes {
            let centre = screenPoint(node.position, in: size)
            let distance = hypot(centre.x - point.x, centre.y - point.y)
            if distance <= screenRadius(node) + 6, distance < (best?.distance ?? .infinity) {
                best = (node.id, distance)
            }
        }
        return best?.id
    }

    /// The link at a point on screen, if any.
    func link(at point: CGPoint, in size: CGSize) -> String? {
        let positions = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, screenPoint($0.position, in: size)) })
        var best: (id: String, distance: CGFloat)? = nil
        for edge in graph.edges {
            guard let a = positions[edge.first], let b = positions[edge.second] else { continue }
            let distance = Self.distance(from: point, toSegment: a, b)
            if distance <= 6, distance < (best?.distance ?? .infinity) {
                best = (edge.id, distance)
            }
        }
        return best?.id
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let along = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + along * dx), point.y - (a.y + along * dy))
    }

    // MARK: - Pointer actions

    func hover(at point: CGPoint?, in size: CGSize) {
        pointerIsOverMap = point != nil
        let found = point.flatMap { thought(at: $0, in: size) }
        if hoveredThought != found {
            hoveredThought = found
        }
    }

    func tap(at point: CGPoint, in size: CGSize) {
        if let id = thought(at: point, in: size) {
            selection = .thought(id)
        } else if let id = link(at: point, in: size) {
            selection = .link(id)
        } else {
            selection = nil
        }
    }

    /// A drag that starts on a dot moves the dot; a drag that starts on empty space moves the map.
    func drag(from start: CGPoint, to current: CGPoint, in size: CGSize, isFirstChange: Bool) {
        if isFirstChange {
            draggedThought = thought(at: start, in: size)
            panAtDragStart = pan
        }
        if let id = draggedThought, let index = graph.nodes.firstIndex(where: { $0.id == id }) {
            graph.nodes[index].position = mapPoint(current, in: size)
        } else {
            pan = CGSize(
                width: panAtDragStart.width + current.x - start.x,
                height: panAtDragStart.height + current.y - start.y
            )
        }
    }

    func endDrag() {
        if draggedThought != nil {
            savePositions()
        }
        draggedThought = nil
    }

    func pinch(_ magnification: CGFloat, isFirstChange: Bool) {
        if isFirstChange {
            zoomAtPinchStart = zoom
        }
        zoom = min(max(zoomAtPinchStart * magnification, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    private func savePositions() {
        let store = self.store
        let current = graph
        Task.detached(priority: .utility) {
            try? store.saveGraph(current)
        }
    }

    // MARK: - Scrolling: a trackpad moves the map, a mouse wheel zooms it

    func startWatchingScroll() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.pointerIsOverMap else { return event }
            if event.hasPreciseScrollingDeltas {
                self.pan = CGSize(
                    width: self.pan.width + event.scrollingDeltaX,
                    height: self.pan.height + event.scrollingDeltaY
                )
            } else {
                let factor = 1 + event.scrollingDeltaY * 0.04
                self.zoom = min(max(self.zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
            }
            return nil
        }
    }

    func stopWatchingScroll() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
        pointerIsOverMap = false
    }

    // MARK: - What stands out

    /// How strongly a thought is drawn: full when nothing is singled out, or when it
    /// is the one under the pointer, the one selected, or linked to that one.
    func emphasis(for node: GraphNode) -> Double {
        if let kind = highlightedKind {
            return node.kind == kind ? 1 : 0.18
        }
        guard let focus = focusedThoughts else { return 1 }
        return focus.contains(node.id) ? 1 : 0.18
    }

    func emphasis(for edge: GraphEdge) -> Double {
        if highlightedKind != nil {
            return 0.25
        }
        if case .link(let id) = selection, hoveredThought == nil {
            return id == edge.id ? 1 : 0.25
        }
        guard let centre = hoveredThought ?? selectedThoughtID else { return 0.8 }
        return edge.first == centre || edge.second == centre ? 1 : 0.2
    }

    private var selectedThoughtID: String? {
        if case .thought(let id) = selection { return id }
        return nil
    }

    /// The thoughts that stand out, or nil when everything is drawn the same.
    private var focusedThoughts: Set<String>? {
        if let hovered = hoveredThought {
            return (neighbours[hovered] ?? []).union([hovered])
        }
        switch selection {
        case .thought(let id):
            return (neighbours[id] ?? []).union([id])
        case .link(let id):
            guard let edge = graph.edges.first(where: { $0.id == id }) else { return nil }
            return [edge.first, edge.second]
        case nil:
            return nil
        }
    }

    // MARK: - Names on the map

    /// A name to draw, and where.
    struct PlacedLabel: Equatable {
        let thoughtID: String
        let label: String
        /// The top-centre of the text, on screen.
        let point: CGPoint
        /// The room the text takes.
        let size: CGSize
        let isFocus: Bool
    }

    /// Which names are written on the map, and where.
    ///
    /// With few thoughts, every name shows. With many, names are placed in order of
    /// importance (whatever is under the pointer or selected, then the most recurring
    /// thoughts) and a name is left out if it would sit on top of another name or
    /// another dot. Zooming in makes room, so more names appear.
    func placedLabels(in size: CGSize, fontName: String) -> [PlacedLabel] {
        let nodes = graph.nodes
        let crowded = nodes.count > 40
        let focus = focusedThoughts ?? []
        let centres = nodes.map { screenPoint($0.position, in: size) }
        let radii = nodes.map { screenRadius($0) }

        let order = nodes.indices.sorted { first, second in
            let firstFocus = focus.contains(nodes[first].id)
            let secondFocus = focus.contains(nodes[second].id)
            if firstFocus != secondFocus { return firstFocus }
            if nodes[first].weight != nodes[second].weight { return nodes[first].weight > nodes[second].weight }
            return nodes[first].id < nodes[second].id
        }

        var placed: [PlacedLabel] = []
        var taken: [CGRect] = []
        for (rank, index) in order.enumerated() {
            let node = nodes[index]
            let centre = centres[index]
            // Nothing far outside the window needs a name.
            guard centre.x > -80, centre.x < size.width + 80, centre.y > -40, centre.y < size.height + 40 else { continue }

            let textSize = labelSize(node.label, fontName: fontName)
            let point = CGPoint(x: centre.x, y: centre.y + radii[index] + 5)
            let rect = CGRect(x: point.x - textSize.width / 2, y: point.y, width: textSize.width, height: textSize.height)
                .insetBy(dx: -4, dy: -2)
            let isFocus = focus.contains(node.id)

            if crowded && !isFocus {
                if taken.contains(where: { $0.intersects(rect) }) {
                    continue
                }
                // Not on top of another thought's dot either, except for the few most
                // recurring thoughts, which are always worth naming.
                var coversADot = false
                for other in nodes.indices where other != index && rank >= 10 {
                    let dot = CGRect(
                        x: centres[other].x - radii[other],
                        y: centres[other].y - radii[other],
                        width: radii[other] * 2,
                        height: radii[other] * 2
                    )
                    if dot.intersects(rect) {
                        coversADot = true
                        break
                    }
                }
                if coversADot { continue }
            }

            taken.append(rect)
            placed.append(PlacedLabel(thoughtID: node.id, label: node.label, point: point, size: textSize, isFocus: isFocus && hasFocus(node.id)))
        }
        return placed
    }

    /// True for the thought under the pointer or the one selected (not merely linked to it).
    private func hasFocus(_ id: String) -> Bool {
        hoveredThought == id || selectedThoughtID == id
    }

    private var labelSizes: [String: CGSize] = [:]

    /// How much room a name takes, worked out once and remembered.
    private func labelSize(_ label: String, fontName: String) -> CGSize {
        let key = fontName + "|" + label
        if let known = labelSizes[key] {
            return known
        }
        let font = NSFont(name: fontName, size: 12) ?? NSFont.systemFont(ofSize: 12)
        let measured = (label as NSString).size(withAttributes: [.font: font])
        let size = CGSize(width: ceil(measured.width), height: ceil(measured.height))
        labelSizes[key] = size
        return size
    }

    // MARK: - The detail panel

    func thoughtDetail(_ id: String) -> MapThoughtDetail? {
        guard let thought = memory.thoughts[id] else { return nil }

        var connections: [String: (label: String, reasons: [String])] = [:]
        func add(_ otherID: String, _ reason: String) {
            guard let other = memory.thoughts[otherID], otherID != id else { return }
            var entry = connections[otherID] ?? (other.label, [])
            if !entry.reasons.contains(reason) {
                entry.reasons.append(reason)
            }
            connections[otherID] = entry
        }
        for link in thought.links {
            add(link.target, link.reason)
        }
        for other in memory.thoughts.values {
            for link in other.links where link.target == id {
                add(other.id, link.reason)
            }
        }

        return MapThoughtDetail(
            id: id,
            label: thought.label,
            kind: thought.kind,
            aliases: thought.aliases,
            summary: thought.summary,
            firstSeen: thought.firstSeen,
            lastSeen: thought.lastSeen,
            shifts: thought.timeline
                .sorted { ($0.date, $0.note) < ($1.date, $1.note) }
                .map { MapThoughtDetail.Shift(date: $0.date, note: $0.note) },
            days: Self.days(from: thought.evidence.map { ($0.entryID, $0.date, $0.quote) }),
            connections: connections
                .map { MapThoughtDetail.Connection(thoughtID: $0.key, label: $0.value.label, reasons: $0.value.reasons, linkID: GraphEdge.id(id, $0.key)) }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        )
    }

    func linkDetail(_ id: String) -> MapLinkDetail? {
        guard let edge = graph.edges.first(where: { $0.id == id }),
              let first = memory.thoughts[edge.first],
              let second = memory.thoughts[edge.second] else {
            return nil
        }
        let evidence = first.links.filter { $0.target == second.id } + second.links.filter { $0.target == first.id }
        return MapLinkDetail(
            id: id,
            firstID: first.id,
            firstLabel: first.label,
            secondID: second.id,
            secondLabel: second.label,
            reasons: edge.reasons,
            days: Self.days(from: evidence.map { ($0.entryID, $0.date, $0.quote) })
        )
    }

    /// Groups quoted lines by the entry they came from, oldest entry first.
    private static func days(from lines: [(entryID: UUID, date: String, quote: String)]) -> [MapDayQuotes] {
        var byEntry: [UUID: (date: String, quotes: [String])] = [:]
        for line in lines {
            var entry = byEntry[line.entryID] ?? (line.date, [])
            if !entry.quotes.contains(line.quote) {
                entry.quotes.append(line.quote)
            }
            byEntry[line.entryID] = entry
        }
        return byEntry
            .map { MapDayQuotes(entryID: $0.key, date: $0.value.date, quotes: $0.value.quotes) }
            .sorted { ($0.date, $0.entryID.uuidString) < ($1.date, $1.entryID.uuidString) }
    }
}
