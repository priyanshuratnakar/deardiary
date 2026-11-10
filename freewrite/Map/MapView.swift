//
//  MapView.swift
//  Dear Diary
//
//  The map: a full-window view of memory as dots and thin lines.
//
//  It keeps to freewrite's look. The background is the page's white or black,
//  names are grey text in the page's font, and the controls are words. The
//  only colour is on the dots, where it shows the kind of thought.
//
//  Drag empty space to move the map, pinch or scroll to zoom, drag a dot to
//  move it. Click a dot or a line to read about it in the panel on the right.
//

import SwiftUI
import AppKit

/// Colours and fonts for the map, taken from the page's current font and theme.
struct MapStyle: Equatable {
    let fontName: String
    let isLight: Bool

    var quietColor: Color { isLight ? .gray : .gray.opacity(0.8) }
    var strongColor: Color { isLight ? .black : .white }
    var bodyColor: Color {
        isLight ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9)
    }
    var backgroundColor: Color { isLight ? .white : .black }
    var lineColor: Color { isLight ? Color(white: 0.55) : Color(white: 0.6) }

    func color(for kind: ThoughtKind) -> Color {
        MapPalette.color(for: kind, isLight: isLight)
    }
}

/// What ContentView places over the window. It owns the map's state, loads
/// memory when it opens, and reloads when memory changes while it is open.
struct MapView: View {
    @StateObject private var model: MapModel
    @ObservedObject private var memoryStatus: MemoryStatus

    let fontName: String
    let colorScheme: ColorScheme
    let onClose: () -> Void
    let onOpenEntry: (UUID) -> Void
    private let mapOpened: () -> Void

    init(
        fontName: String,
        colorScheme: ColorScheme,
        onClose: @escaping () -> Void,
        onOpenEntry: @escaping (UUID) -> Void,
        store: MemoryStore = MemoryStore(),
        memoryStatus: MemoryStatus = MemoryEngine.shared.status,
        mapOpened: @escaping () -> Void = { MemoryEngine.shared.nudge(includeFresh: true) }
    ) {
        _model = StateObject(wrappedValue: MapModel(store: store))
        self.memoryStatus = memoryStatus
        self.fontName = fontName
        self.colorScheme = colorScheme
        self.onClose = onClose
        self.onOpenEntry = onOpenEntry
        self.mapOpened = mapOpened
    }

    var body: some View {
        MapScreen(
            model: model,
            style: MapStyle(fontName: fontName, isLight: colorScheme == .light),
            problem: memoryStatus.summary.problem,
            fitOnAppear: true,
            onClose: onClose,
            onOpenEntry: onOpenEntry
        )
        .task {
            await model.load()
        }
        .onAppear {
            // Typing must not reach the page hidden underneath.
            NSApp.keyWindow?.makeFirstResponder(nil)
            model.startWatchingScroll()
            // Opening the map is one of the moments an entry counts as settled for memory.
            mapOpened()
        }
        .onDisappear {
            model.stopWatchingScroll()
        }
        .onChange(of: memoryStatus.summary.lastUpdated) { _, _ in
            // Memory changed while the map was open: bring in the new thoughts.
            Task { await model.load() }
        }
    }
}

/// The map itself: the canvas, the words along the bottom, and the detail panel.
struct MapScreen: View {
    @ObservedObject var model: MapModel
    let style: MapStyle
    var problem: String? = nil
    var fitOnAppear = false
    let onClose: () -> Void
    let onOpenEntry: (UUID) -> Void

    @State private var hasFitted = false

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    style.backgroundColor

                    if model.isLoading {
                        EmptyView()
                    } else if model.graph.isEmpty {
                        emptyState
                    } else {
                        canvas(size: geometry.size)
                    }

                    VStack(spacing: 0) {
                        Spacer()
                        if let problem {
                            Text(problem)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                        }
                        bottomBar(size: geometry.size)
                    }
                }
                .onChange(of: model.isLoading) { _, loading in
                    if !loading, fitOnAppear, !hasFitted {
                        hasFitted = true
                        model.fit(in: geometry.size)
                    }
                }
            }

            if let selection = model.selection {
                Divider()
                MapDetailView(
                    model: model,
                    selection: selection,
                    style: style,
                    onOpenEntry: onOpenEntry
                )
                .frame(width: 340)
            }
        }
        .background(style.backgroundColor)
    }

    // MARK: - The canvas

    private func canvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            draw(in: &context, size: canvasSize)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    model.drag(from: value.startLocation, to: value.location, in: size, isFirstChange: !isDragging)
                    isDragging = true
                }
                .onEnded { _ in
                    isDragging = false
                    model.endDrag()
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    model.pinch(value.magnification, isFirstChange: !isPinching)
                    isPinching = true
                }
                .onEnded { _ in
                    isPinching = false
                }
        )
        .onTapGesture(coordinateSpace: .local) { location in
            model.tap(at: location, in: size)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                model.hover(at: location, in: size)
            case .ended:
                model.hover(at: nil, in: size)
            }
        }
    }

    @State private var isDragging = false
    @State private var isPinching = false

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let graph = model.graph
        let positions = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, model.screenPoint($0.position, in: size)) })

        // Lines first, so dots sit on top of them.
        for edge in graph.edges {
            guard let from = positions[edge.first], let to = positions[edge.second] else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            let emphasis = model.emphasis(for: edge)
            let width = (1 + min(CGFloat(edge.count - 1), 2) * 0.5) * (emphasis >= 1 ? 1.4 : 1)
            context.stroke(path, with: .color(style.lineColor.opacity(0.55 * emphasis)), lineWidth: width)
        }

        // Dots, each with a thin ring of background so overlapping dots stay distinct.
        for node in graph.nodes {
            guard let centre = positions[node.id] else { continue }
            let radius = model.screenRadius(node)
            let emphasis = model.emphasis(for: node)
            let circle = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            let ring = Path(ellipseIn: CGRect(x: centre.x - radius - 2, y: centre.y - radius - 2, width: radius * 2 + 4, height: radius * 2 + 4))
            context.fill(ring, with: .color(style.backgroundColor))
            context.fill(circle, with: .color(style.color(for: node.kind).opacity(emphasis)))

            if model.selection == .thought(node.id) || model.hoveredThought == node.id {
                let outline = Path(ellipseIn: CGRect(x: centre.x - radius - 4, y: centre.y - radius - 4, width: radius * 2 + 8, height: radius * 2 + 8))
                context.stroke(outline, with: .color(style.strongColor.opacity(0.7)), lineWidth: 1)
            }
        }

        // Names, in the page's font, grey. A name never wears the dot's colour.
        let emphasisByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, model.emphasis(for: $0)) })
        for label in model.placedLabels(in: size, fontName: style.fontName) {
            let emphasis = emphasisByID[label.thoughtID] ?? 1
            // A soft patch of background behind the name keeps it readable over dots and lines.
            let patch = CGRect(x: label.point.x - label.size.width / 2 - 3, y: label.point.y - 1, width: label.size.width + 6, height: label.size.height + 2)
            context.fill(Path(roundedRect: patch, cornerRadius: 3), with: .color(style.backgroundColor.opacity(0.8)))
            let text = Text(label.label)
                .font(.custom(style.fontName, size: 12))
                .foregroundColor((label.isFocus ? style.strongColor : style.quietColor).opacity(max(emphasis, 0.35)))
            context.draw(context.resolve(text), at: label.point, anchor: .top)
        }

        // The kind of the thought under the pointer, in words, so colour is never the only clue.
        if let hovered = model.hoveredThought,
           let node = graph.nodes.first(where: { $0.id == hovered }),
           let centre = positions[hovered] {
            let text = Text(node.kind.rawValue)
                .font(.system(size: 10))
                .foregroundColor(style.quietColor)
            context.draw(context.resolve(text), at: CGPoint(x: centre.x, y: centre.y - model.screenRadius(node) - 6), anchor: .bottom)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing in memory yet")
                .font(.custom(style.fontName, size: 18))
                .foregroundColor(style.bodyColor)
            Text("Turn memory on in Settings. Thoughts appear here as your entries settle.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - The words along the bottom

    private func bottomBar(size: CGSize) -> some View {
        HStack(spacing: 8) {
            MapWord(title: "Close", style: style, action: onClose)
                .keyboardShortcut(.cancelAction)

            if !model.graph.isEmpty {
                Text("•").foregroundColor(.gray)
                MapWord(title: "Fit", style: style) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.fit(in: size)
                    }
                }
            }

            Spacer()

            // The legend: what each colour means, in words.
            ForEach(kindsOnTheMap, id: \.self) { kind in
                HStack(spacing: 5) {
                    Circle()
                        .fill(style.color(for: kind))
                        .frame(width: 8, height: 8)
                    Text(kind.rawValue.capitalized)
                        .font(.system(size: 13))
                        .foregroundColor(model.highlightedKind == kind ? style.strongColor : style.quietColor)
                }
                .padding(.leading, 6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    model.highlightedKind = hovering ? kind : nil
                }
            }
        }
        .padding(8)
        .padding()
        .background(style.backgroundColor.opacity(0.9))
    }

    /// The kinds that actually appear, in a fixed order, so a colour always means the same thing.
    private var kindsOnTheMap: [ThoughtKind] {
        let present = Set(model.graph.nodes.map(\.kind))
        return ThoughtKind.allCases.filter { present.contains($0) }
    }
}

/// A clickable word on the map, in the bottom bar's style.
struct MapWord: View {
    let title: String
    let style: MapStyle
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundColor(isHovering ? style.strongColor : style.quietColor)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

/// The "Map" word in freewrite's bottom bar. It shows when AI is on and a key is saved.
struct MapWordButton: View {
    @Binding var isShowingMap: Bool
    let textColor: Color
    let textHoverColor: Color
    @Binding var isHoveringBottomNav: Bool

    @State private var isHovering = false

    var body: some View {
        Button("Map") {
            isShowingMap = true
        }
        .buttonStyle(.plain)
        .foregroundColor(isHovering ? textHoverColor : textColor)
        .onHover { hovering in
            isHovering = hovering
            isHoveringBottomNav = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
