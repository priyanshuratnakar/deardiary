//
//  GraphLayout.swift
//  Dear Diary
//
//  Decides where the dots sit.
//
//  The map settles once and then stays still. Dots that are joined pull
//  together, dots that are near each other push apart, and everything is held
//  loosely around the middle. A thought that many days touch pushes harder,
//  so it keeps room for its own fan of days around it. The result is a round
//  cloud of hubs and fans.
//
//  Dots that already have a remembered position are not moved: only new dots
//  are placed, near what they are joined to.
//
//  The same input always gives the same picture. Nothing here is random.
//

import Foundation
import CoreGraphics

enum GraphLayout {
    struct Settings {
        /// How far apart two linked thoughts like to sit.
        var restLength: Double = 150
        /// How far a day likes to sit from a thought it touched, beyond the thought's own size.
        var dayLength: Double = 46
        /// How strongly two nearby dots push apart.
        var repulsion: Double = 9_000
        /// Beyond this distance two dots do not push each other at all.
        var reach: Double = 190
        /// How strongly a line pulls its two ends together.
        var spring: Double = 0.06
        /// How strongly everything is held around the middle.
        var gravity: Double = 0.010
        /// How many rounds of small moves are made before it stops.
        var rounds = 300
        /// Clear space kept between two thoughts, beyond their own sizes.
        var gap: Double = 26
        /// Clear space kept around a day.
        var dayGap: Double = 6
        /// A thought with at least this many lines counts as busy.
        var busyFrom = 6
        /// How strongly two busy thoughts push each other when they are far apart.
        var farRepulsion: Double = 4_500
    }

    /// Places the dots named in `moving` and leaves every other dot exactly where it is.
    static func settle(_ graph: MemoryGraph, moving: Set<String>, settings: Settings = Settings()) -> MemoryGraph {
        let count = graph.nodes.count
        guard count > 0, !moving.isEmpty else { return graph }

        let index = Dictionary(uniqueKeysWithValues: graph.nodes.enumerated().map { ($1.id, $0) })
        let movable = graph.nodes.map { moving.contains($0.id) }
        let isDay = graph.nodes.map(\.isDay)
        let radii = graph.nodes.map { Double($0.radius) }
        let links: [(Int, Int)] = graph.edges.compactMap { edge in
            guard let a = index[edge.first], let b = index[edge.second] else { return nil }
            return (a, b)
        }
        let anyFixed = movable.contains(false)

        var neighbours = [[Int]](repeating: [], count: count)
        for (a, b) in links {
            neighbours[a].append(b)
            neighbours[b].append(a)
        }

        // A thought with many lines is heavier: it pushes harder and so keeps room around it.
        // A day is light.
        let mass: [Double] = (0..<count).map { i in
            isDay[i] ? 0.3 : 1 + 0.2 * Double(min(neighbours[i].count, 60))
        }
        // The busiest thoughts also push each other from far away, so each ends up with
        // its own part of the map instead of all of them crowding the middle.
        let busy = (0..<count).filter { !isDay[$0] && neighbours[$0].count >= settings.busyFrom }
        // How long each line likes to be. A thought that many days touch needs a wider
        // ring around it for them all to fit.
        let rest: [Double] = links.map { a, b in
            if isDay[a] || isDay[b] {
                let thought = isDay[a] ? b : a
                return settings.dayLength + radii[thought] + min(1.1 * Double(neighbours[thought].count), 170)
            }
            return settings.restLength + 3 * Double(min(neighbours[a].count, neighbours[b].count, 40))
        }

        var x = graph.nodes.map { Double($0.position.x) }
        var y = graph.nodes.map { Double($0.position.y) }

        // 1. A starting place for each new dot.
        let fixedIndices = (0..<count).filter { !movable[$0] }
        let centreX = fixedIndices.isEmpty ? 0 : fixedIndices.map { x[$0] }.reduce(0, +) / Double(fixedIndices.count)
        let centreY = fixedIndices.isEmpty ? 0 : fixedIndices.map { y[$0] }.reduce(0, +) / Double(fixedIndices.count)
        let reachOfFixed = fixedIndices.map { ((x[$0] - centreX) * (x[$0] - centreX) + (y[$0] - centreY) * (y[$0] - centreY)).squareRoot() }.max() ?? 0

        // Thoughts first.
        var placedSoFar = 0
        var hasPlace = movable.map { !$0 }
        for i in 0..<count where movable[i] && !isDay[i] {
            let anchors = neighbours[i].filter { !movable[$0] }
            let nudge = jitter(for: graph.nodes[i].id)
            if !anchors.isEmpty {
                // Next to what it is joined to.
                x[i] = anchors.map { x[$0] }.reduce(0, +) / Double(anchors.count) + nudge.x * settings.restLength * 0.6
                y[i] = anchors.map { y[$0] }.reduce(0, +) / Double(anchors.count) + nudge.y * settings.restLength * 0.6
            } else {
                // On a widening spiral, outside whatever is already placed.
                let step = Double(placedSoFar)
                let distance = reachOfFixed + (anyFixed ? settings.restLength : 0) + settings.restLength * 0.55 * (step + 1).squareRoot()
                let angle = step * 2.399963229728653
                x[i] = centreX + distance * cos(angle) + nudge.x * 4
                y[i] = centreY + distance * sin(angle) + nudge.y * 4
            }
            hasPlace[i] = true
            placedSoFar += 1
        }
        // Then days, each beside the thoughts it touched.
        for i in 0..<count where movable[i] && isDay[i] {
            let anchors = neighbours[i].filter { hasPlace[$0] }
            let nudge = jitter(for: graph.nodes[i].id)
            if !anchors.isEmpty {
                x[i] = anchors.map { x[$0] }.reduce(0, +) / Double(anchors.count) + nudge.x * settings.dayLength
                y[i] = anchors.map { y[$0] }.reduce(0, +) / Double(anchors.count) + nudge.y * settings.dayLength
            } else {
                x[i] = centreX + nudge.x * settings.restLength
                y[i] = centreY + nudge.y * settings.restLength
            }
            hasPlace[i] = true
        }

        // 2. Many small moves, each smaller than the last.
        var moveX = [Double](repeating: 0, count: count)
        var moveY = [Double](repeating: 0, count: count)
        let rounds = count > 500 ? settings.rounds * 2 / 3 : settings.rounds
        let reachSquared = settings.reach * settings.reach

        for round in 0..<rounds {
            for i in 0..<count {
                moveX[i] = 0
                moveY[i] = 0
            }

            // Nearby dots push apart. Dots are sorted into squares the size of the reach,
            // so each one is only compared with those in its own square and the eight around it.
            let squares = Squares(x: x, y: y, size: settings.reach)
            for i in 0..<count {
                squares.forEachNear(i) { j in
                    guard j > i, movable[i] || movable[j] else { return }
                    var dx = x[i] - x[j]
                    var dy = y[i] - y[j]
                    var squared = dx * dx + dy * dy
                    guard squared <= reachSquared else { return }
                    if squared < 0.01 {
                        // Two dots on the same spot: push them apart in a fixed direction.
                        dx = 0.1 + Double(i % 7) * 0.01
                        dy = 0.1 + Double(j % 5) * 0.01
                        squared = dx * dx + dy * dy
                    }
                    let distance = squared.squareRoot()
                    let push = settings.repulsion * mass[i] * mass[j] / squared
                    let pushX = dx / distance * push
                    let pushY = dy / distance * push
                    moveX[i] += pushX
                    moveY[i] += pushY
                    moveX[j] -= pushX
                    moveY[j] -= pushY
                }
            }

            // Busy thoughts push each other from any distance.
            for (position, i) in busy.enumerated() {
                for j in busy[(position + 1)...] where movable[i] || movable[j] {
                    let dx = x[i] - x[j]
                    let dy = y[i] - y[j]
                    let squared = dx * dx + dy * dy
                    // Up close, the push above has already been counted.
                    guard squared > reachSquared else { continue }
                    let distance = squared.squareRoot()
                    let push = settings.farRepulsion * mass[i] * mass[j] / squared
                    let pushX = dx / distance * push
                    let pushY = dy / distance * push
                    moveX[i] += pushX
                    moveY[i] += pushY
                    moveX[j] -= pushX
                    moveY[j] -= pushY
                }
            }

            // Joined dots pull together.
            for (number, link) in links.enumerated() {
                let (a, b) = link
                let dx = x[b] - x[a]
                let dy = y[b] - y[a]
                let distance = max((dx * dx + dy * dy).squareRoot(), 0.01)
                let pull = (distance - rest[number]) * settings.spring
                let pullX = dx / distance * pull
                let pullY = dy / distance * pull
                moveX[a] += pullX
                moveY[a] += pullY
                moveX[b] -= pullX
                moveY[b] -= pullY
            }

            // Everything is held loosely around the middle.
            for i in 0..<count {
                moveX[i] -= (x[i] - centreX) * settings.gravity
                moveY[i] -= (y[i] - centreY) * settings.gravity
            }

            let cooling = 1 - Double(round) / Double(rounds)
            let largestStep = 2 + 38 * cooling
            for i in 0..<count where movable[i] {
                let length = (moveX[i] * moveX[i] + moveY[i] * moveY[i]).squareRoot()
                guard length > 0 else { continue }
                let scale = min(length, largestStep) / length
                x[i] += moveX[i] * scale
                y[i] += moveY[i] * scale
            }
        }

        // 3. Make sure no two dots overlap.
        let widest = 2 * (radii.max() ?? 0) + settings.gap
        for _ in 0..<12 {
            var touched = false
            let squares = Squares(x: x, y: y, size: widest)
            for i in 0..<count {
                squares.forEachNear(i) { j in
                    guard j > i, movable[i] || movable[j] else { return }
                    let dx = x[i] - x[j]
                    let dy = y[i] - y[j]
                    let distance = max((dx * dx + dy * dy).squareRoot(), 0.01)
                    let wanted = radii[i] + radii[j] + (isDay[i] || isDay[j] ? settings.dayGap : settings.gap)
                    guard distance < wanted else { return }
                    touched = true
                    let shift = (wanted - distance) / distance
                    let share = (movable[i] && movable[j]) ? 0.5 : 1.0
                    if movable[i] {
                        x[i] += dx * shift * share
                        y[i] += dy * shift * share
                    }
                    if movable[j] {
                        x[j] -= dx * shift * share
                        y[j] -= dy * shift * share
                    }
                }
            }
            if !touched { break }
        }

        // 4. A fresh map is centred on its own middle.
        if !anyFixed {
            let middleX = x.reduce(0, +) / Double(count)
            let middleY = y.reduce(0, +) / Double(count)
            for i in 0..<count {
                x[i] -= middleX
                y[i] -= middleY
            }
        }

        var result = graph
        for i in 0..<count where movable[i] && x[i].isFinite && y[i].isFinite {
            result.nodes[i].position = CGPoint(x: x[i], y: y[i])
        }
        return result
    }

    /// Dots sorted into a grid of squares, so that "which dots are near this one" does not
    /// mean looking at every dot. Within a square, dots are kept in their own order, so the
    /// same input always gives the same sums.
    private struct Squares {
        private let size: Double
        private let column: [Int]
        private let row: [Int]
        private var members: [Int64: [Int]] = [:]

        init(x: [Double], y: [Double], size: Double) {
            self.size = max(size, 1)
            column = x.map { Int(($0 / max(size, 1)).rounded(.down)) }
            row = y.map { Int(($0 / max(size, 1)).rounded(.down)) }
            for i in x.indices {
                members[Self.key(column[i], row[i]), default: []].append(i)
            }
        }

        private static func key(_ column: Int, _ row: Int) -> Int64 {
            (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF)
        }

        /// Calls `body` with every dot in the same square as `i` or in one of the eight around it.
        func forEachNear(_ i: Int, _ body: (Int) -> Void) {
            for across in -1...1 {
                for down in -1...1 {
                    guard let list = members[Self.key(column[i] + across, row[i] + down)] else { continue }
                    for j in list {
                        body(j)
                    }
                }
            }
        }
    }

    /// A small, fixed offset worked out from a dot's id, so that two new dots
    /// joined to the same place do not land on top of each other.
    /// The same id always gives the same offset.
    static func jitter(for id: String) -> (x: Double, y: Double) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let angle = Double(hash % 3600) / 3600 * 2 * Double.pi
        let distance = 0.5 + Double((hash >> 16) % 500) / 1000
        return (cos(angle) * distance, sin(angle) * distance)
    }
}
