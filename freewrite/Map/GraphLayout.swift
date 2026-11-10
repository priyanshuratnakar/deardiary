//
//  GraphLayout.swift
//  Dear Diary
//
//  Decides where the dots sit.
//
//  The map settles once and then stays still. Linked thoughts pull together,
//  all thoughts push apart a little, and everything is held loosely around the
//  middle. Dots that already have a remembered position are not moved: only
//  new thoughts are placed, near what they are linked to.
//
//  The same input always gives the same picture. Nothing here is random.
//

import Foundation
import CoreGraphics

enum GraphLayout {
    struct Settings {
        /// How far apart two linked thoughts like to sit.
        var restLength: Double = 120
        /// How strongly every pair of thoughts pushes apart.
        var repulsion: Double = 14_000
        /// How strongly a link pulls its two ends together.
        var spring: Double = 0.06
        /// How strongly everything is held around the middle.
        var gravity: Double = 0.012
        /// How many rounds of small moves are made before it stops.
        var rounds = 320
        /// Clear space kept between two dots, beyond their own sizes.
        var gap: Double = 26
    }

    /// Places the dots named in `moving` and leaves every other dot exactly where it is.
    static func settle(_ graph: MemoryGraph, moving: Set<String>, settings: Settings = Settings()) -> MemoryGraph {
        let count = graph.nodes.count
        guard count > 0, !moving.isEmpty else { return graph }

        let index = Dictionary(uniqueKeysWithValues: graph.nodes.enumerated().map { ($1.id, $0) })
        let movable = graph.nodes.map { moving.contains($0.id) }
        let radii = graph.nodes.map { Double($0.radius) }
        let links: [(Int, Int)] = graph.edges.compactMap { edge in
            guard let a = index[edge.first], let b = index[edge.second] else { return nil }
            return (a, b)
        }
        let anyFixed = movable.contains(false)

        var x = graph.nodes.map { Double($0.position.x) }
        var y = graph.nodes.map { Double($0.position.y) }

        // 1. A starting place for each new dot.
        let fixedIndices = (0..<count).filter { !movable[$0] }
        let centreX = fixedIndices.isEmpty ? 0 : fixedIndices.map { x[$0] }.reduce(0, +) / Double(fixedIndices.count)
        let centreY = fixedIndices.isEmpty ? 0 : fixedIndices.map { y[$0] }.reduce(0, +) / Double(fixedIndices.count)
        let reach = fixedIndices.map { ((x[$0] - centreX) * (x[$0] - centreX) + (y[$0] - centreY) * (y[$0] - centreY)).squareRoot() }.max() ?? 0

        var neighbours = [[Int]](repeating: [], count: count)
        for (a, b) in links {
            neighbours[a].append(b)
            neighbours[b].append(a)
        }

        var placedSoFar = 0
        for i in 0..<count where movable[i] {
            let anchors = neighbours[i].filter { !movable[$0] }
            let nudge = jitter(for: graph.nodes[i].id)
            if !anchors.isEmpty {
                // Next to the thoughts it is linked to.
                x[i] = anchors.map { x[$0] }.reduce(0, +) / Double(anchors.count) + nudge.x * settings.restLength * 0.6
                y[i] = anchors.map { y[$0] }.reduce(0, +) / Double(anchors.count) + nudge.y * settings.restLength * 0.6
            } else {
                // On a widening spiral, outside whatever is already placed.
                let step = Double(placedSoFar)
                let distance = reach + (anyFixed ? settings.restLength : 0) + settings.restLength * 0.55 * (step + 1).squareRoot()
                let angle = step * 2.399963229728653
                x[i] = centreX + distance * cos(angle) + nudge.x * 4
                y[i] = centreY + distance * sin(angle) + nudge.y * 4
            }
            placedSoFar += 1
        }

        // 2. Many small moves, each smaller than the last.
        var moveX = [Double](repeating: 0, count: count)
        var moveY = [Double](repeating: 0, count: count)

        for round in 0..<settings.rounds {
            for i in 0..<count {
                moveX[i] = 0
                moveY[i] = 0
            }

            // Every pair pushes apart.
            for i in 0..<count {
                for j in (i + 1)..<count where movable[i] || movable[j] {
                    var dx = x[i] - x[j]
                    var dy = y[i] - y[j]
                    var squared = dx * dx + dy * dy
                    if squared < 0.01 {
                        // Two dots on the same spot: push them apart in a fixed direction.
                        dx = 0.1 + Double(i % 7) * 0.01
                        dy = 0.1 + Double(j % 5) * 0.01
                        squared = dx * dx + dy * dy
                    }
                    let distance = squared.squareRoot()
                    let push = settings.repulsion / squared
                    let pushX = dx / distance * push
                    let pushY = dy / distance * push
                    moveX[i] += pushX
                    moveY[i] += pushY
                    moveX[j] -= pushX
                    moveY[j] -= pushY
                }
            }

            // Linked thoughts pull together.
            for (a, b) in links {
                let dx = x[b] - x[a]
                let dy = y[b] - y[a]
                let distance = max((dx * dx + dy * dy).squareRoot(), 0.01)
                let pull = (distance - settings.restLength) * settings.spring
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

            let cooling = 1 - Double(round) / Double(settings.rounds)
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
        for _ in 0..<12 {
            var touched = false
            for i in 0..<count {
                for j in (i + 1)..<count where movable[i] || movable[j] {
                    let dx = x[i] - x[j]
                    let dy = y[i] - y[j]
                    let distance = max((dx * dx + dy * dy).squareRoot(), 0.01)
                    let wanted = radii[i] + radii[j] + settings.gap
                    guard distance < wanted else { continue }
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

    /// A small, fixed offset worked out from a thought's id, so that two new
    /// thoughts linked to the same place do not land on top of each other.
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
