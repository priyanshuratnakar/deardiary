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
    /// The small grey dot for a day. Days are not a kind of thought, so they take no colour.
    var dayColor: Color { isLight ? Color(white: 0.62) : Color(white: 0.55) }

    func color(for kind: ThoughtKind) -> Color {
        MapPalette.color(for: kind, isLight: isLight)
    }
}

/// What ContentView places over the window. It owns the map's state, loads
/// memory when it opens, and reloads when memory changes while it is open.
struct MapView: View {
    @StateObject private var model: MapModel
    @ObservedObject private var memoryStatus: MemoryStatus
    @ObservedObject private var settings: AISettings
    @Environment(\.openSettings) private var openSettings

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
        settings: AISettings = .shared,
        mapOpened: @escaping () -> Void = { MemoryEngine.shared.nudge(includeFresh: true) }
    ) {
        _model = StateObject(wrappedValue: MapModel(store: store))
        self.memoryStatus = memoryStatus
        self.settings = settings
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
            emptyBecause: MapEmptyReason.current(settings),
            onOpenSettings: { openSettings() },
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

/// Why there is nothing on the map yet. Each has its own plain line.
enum MapEmptyReason: Equatable {
    /// No AI is set up, so nothing can build memory.
    case noAI
    /// AI is set up but memory is switched off.
    case memoryOff
    /// Memory is on and simply has nothing yet.
    case waiting

    static func current(_ settings: AISettings) -> MapEmptyReason {
        if !settings.isReady { return .noAI }
        return settings.memoryEnabled ? .waiting : .memoryOff
    }

    var line: String {
        switch self {
        case .noAI:
            return "Memory is built by an AI that reads each entry after you have finished with it."
        case .memoryOff:
            return "Turn memory on in Settings and thoughts will appear here as you write."
        case .waiting:
            return "Thoughts appear here once an entry has settled, about ten minutes after you stop writing."
        }
    }

    /// The word that opens Settings, when Settings is where the next step is.
    var settingsWord: String? {
        switch self {
        case .noAI: return "Set it up in Settings"
        case .memoryOff: return "Open Settings"
        case .waiting: return nil
        }
    }
}

/// The map itself: the canvas, the words along the bottom, and the detail panel.
struct MapScreen: View {
    @ObservedObject var model: MapModel
    let style: MapStyle
    var problem: String? = nil
    var fitOnAppear = false
    /// Why the map is empty, when it is, so it can say what to do next.
    var emptyBecause: MapEmptyReason = .waiting
    var onOpenSettings: () -> Void = {}
    let onClose: () -> Void
    let onOpenEntry: (UUID) -> Void

    @State private var hasFitted = false
    @FocusState private var isTypingFind: Bool

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
                        if let hint = linkHint {
                            // One plain line while a thought is held over another.
                            Text(hint)
                                .font(.system(size: 13))
                                .foregroundColor(style.bodyColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                // A patch of background, so the line reads over whatever is behind it.
                                .background(style.backgroundColor.opacity(0.92))
                                .padding(.bottom, 4)
                        }
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

        // Lines first, so dots sit on top of them: thin and straight. The line from a day
        // to a thought is fainter than a link between two thoughts.
        for edge in graph.edges {
            guard let from = positions[edge.first], let to = positions[edge.second] else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            let emphasis = model.emphasis(for: edge)
            if edge.isDayLink {
                context.stroke(path, with: .color(style.lineColor.opacity(0.42 * emphasis)), lineWidth: emphasis >= 1 ? 1 : 0.7)
            } else {
                let width = (1 + min(CGFloat(edge.count - 1), 2) * 0.5) * (emphasis >= 1 ? 1.4 : 1)
                context.stroke(path, with: .color(style.lineColor.opacity(0.6 * emphasis)), lineWidth: width)
            }
        }

        // While a thought is held over another: a dotted circle where it came from.
        if model.dropTarget != nil, let dragged = model.draggedThought, let start = model.dragStart,
           let node = graph.nodes.first(where: { $0.id == dragged }) {
            let home = model.screenPoint(start, in: size)
            let radius = model.screenRadius(node)
            let circle = Path(ellipseIn: CGRect(x: home.x - radius, y: home.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(circle, with: .color(style.lineColor.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }

        // Days: small grey dots, under the thoughts.
        for node in graph.nodes where node.isDay {
            guard let centre = positions[node.id] else { continue }
            let radius = model.screenRadius(node)
            let circle = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            context.fill(circle, with: .color(style.dayColor.opacity(model.emphasis(for: node))))
            if model.selection == .day(node.entryID ?? UUID()) || model.hoveredThought == node.id {
                let outline = Path(ellipseIn: CGRect(x: centre.x - radius - 3, y: centre.y - radius - 3, width: radius * 2 + 6, height: radius * 2 + 6))
                context.stroke(outline, with: .color(style.strongColor.opacity(0.7)), lineWidth: 1)
            }
        }

        // Thoughts, each with a thin ring of background so overlapping dots stay distinct.
        for node in graph.nodes where !node.isDay {
            guard let centre = positions[node.id], let kind = node.kind else { continue }
            let radius = model.screenRadius(node)
            let emphasis = model.emphasis(for: node)
            let circle = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            let ring = Path(ellipseIn: CGRect(x: centre.x - radius - 2, y: centre.y - radius - 2, width: radius * 2 + 4, height: radius * 2 + 4))
            context.fill(ring, with: .color(style.backgroundColor))
            context.fill(circle, with: .color(style.color(for: kind).opacity(emphasis)))

            if model.selection == .thought(node.id) || model.hoveredThought == node.id || model.dropTarget == node.id {
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
            let text = Text(node.kind?.rawValue ?? "day")
                .font(.system(size: 10))
                .foregroundColor(style.quietColor)
            context.draw(context.resolve(text), at: CGPoint(x: centre.x, y: centre.y - model.screenRadius(node) - 6), anchor: .bottom)
        }
    }

    /// What letting go will do, while one thought is held over another.
    private var linkHint: String? {
        guard let dragged = model.draggedThought, let target = model.dropTarget else { return nil }
        return "Let go to link \(model.label(of: dragged)) and \(model.label(of: target))"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing in memory yet")
                .font(.custom(style.fontName, size: 18))
                .foregroundColor(style.bodyColor)
            Text(emptyBecause.line)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            if let word = emptyBecause.settingsWord {
                MapWord(title: word, style: style, action: onOpenSettings)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - The words along the bottom

    private func bottomBar(size: CGSize) -> some View {
        HStack(spacing: 8) {
            MapWord(title: "Close", style: style) {
                // Esc first backs out of a fix that is part-way through, then out of "Find".
                if model.pending != nil {
                    model.pending = nil
                } else if model.isFinding {
                    model.stopFinding()
                } else {
                    onClose()
                }
            }
            .keyboardShortcut(.cancelAction)

            if !model.graph.isEmpty {
                Text("•").foregroundColor(.gray)
                MapWord(title: "Fit", style: style) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.fit(in: size)
                    }
                }
                Text("•").foregroundColor(.gray)
                if model.isFinding {
                    // "Find" turns into a line to type in.
                    TextField("Find", text: $model.query, prompt: Text("A name").foregroundColor(style.isLight ? .gray.opacity(0.5) : .gray.opacity(0.6)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(style.strongColor)
                        .frame(width: 130)
                        .focused($isTypingFind)
                        .onAppear { isTypingFind = true }
                        .onSubmit { model.openFirstMatch(in: size) }
                    if let summary = model.findSummary {
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundColor(style.isLight ? .gray.opacity(0.6) : .gray.opacity(0.7))
                    }
                } else {
                    MapWord(title: "Find", style: style) {
                        model.isFinding = true
                    }
                    // How much is on the map, while there is room to say so.
                    if model.selection == nil, let count = model.countLine {
                        Text(count)
                            .font(.system(size: 13))
                            .foregroundColor(style.isLight ? .gray.opacity(0.6) : .gray.opacity(0.7))
                            .padding(.leading, 10)
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
            if !model.graph.days.isEmpty {
                HStack(spacing: 5) {
                    Circle()
                        .fill(style.dayColor)
                        .frame(width: 6, height: 6)
                    Text("Day")
                        .font(.system(size: 13))
                        .foregroundColor(style.quietColor)
                }
                .padding(.leading, 6)
            }
        }
        .padding(8)
        .padding()
        .background(style.backgroundColor.opacity(0.9))
    }

    /// The kinds that actually appear, in a fixed order, so a colour always means the same thing.
    private var kindsOnTheMap: [ThoughtKind] {
        let present = Set(model.graph.nodes.compactMap(\.kind))
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

/// The "Memory" word in freewrite's bottom bar. It is always there, so memory can be found.
struct MapWordButton: View {
    @Binding var isShowingMap: Bool
    let textColor: Color
    let textHoverColor: Color
    @Binding var isHoveringBottomNav: Bool

    @State private var isHovering = false

    var body: some View {
        Button("Memory") {
            isShowingMap = true
        }
        // A mark in place of the word: a thought with the days around it.
        .buttonStyle(BarMark(.memory))
        .barName("Memory")
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
