//
//  VersionsView.swift
//  Dear Diary
//
//  An entry's earlier versions, shown over the whole window the way the map
//  is. The chosen version is on the left, in the page's own font and size,
//  read only. The list of times is on the right, styled like History.
//  "Restore this version" puts that text back on the page; the entry as it
//  reads now is kept as a version first, so a restore can always be undone.
//
//  It is opened from a small icon in a History row, which shows only for
//  entries that have an earlier version.
//

import SwiftUI
import AppKit

/// Small helpers for version text. They touch no files.
enum VersionText {
    static func words(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    static func wordsLine(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }

    /// The text as the page shows it. freewrite drops blank lines at the very top when it opens an entry.
    static func forPage(_ text: String) -> String {
        String(text.drop(while: { $0 == "\n" }))
    }

    static func same(_ one: String, _ other: String) -> Bool {
        forPage(one) == forPage(other)
    }

    /// The time of day, the way this Mac writes it (for example 21:10 or 9:10 PM).
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// The day, written the way History writes it (for example Nov 10).
    static func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

/// One line in the list of versions.
struct VersionRow: Equatable, Identifiable {
    let version: EntryVersion
    let text: String
    let words: Int
    /// True if this is exactly how the entry reads now.
    let isCurrent: Bool

    var id: String { version.id }
}

@MainActor
final class VersionsModel: ObservableObject {
    /// Newest first.
    @Published private(set) var rows: [VersionRow] = []
    @Published private(set) var isLoading = true
    @Published var selectedID: String? = nil
    /// When the entry was started, for the heading.
    @Published private(set) var entryStartedAt: Date? = nil
    /// A plain sentence when a restore could not be done, otherwise nil.
    @Published private(set) var note: String? = nil

    let entryID: UUID
    private let store: SnapshotStore
    private let journal: JournalReader
    private let keep: (String, UUID) async -> Bool

    init(
        entryID: UUID,
        store: SnapshotStore = SnapshotStore(),
        journal: JournalReader = JournalReader(),
        keep: @escaping (String, UUID) async -> Bool = { await SnapshotKeeper.shared.keep($0, for: $1) }
    ) {
        self.entryID = entryID
        self.store = store
        self.journal = journal
        self.keep = keep
    }

    var selected: VersionRow? {
        rows.first { $0.id == selectedID }
    }

    /// Reads the versions and the entry as it stands, off the main thread.
    func load() async {
        let store = self.store
        let journal = self.journal
        let entryID = self.entryID

        let loaded = await Task.detached(priority: .userInitiated) { () -> (Date?, [VersionRow]) in
            let file = journal.entryFiles()?.first { $0.id == entryID }
            let current = file.flatMap { journal.text(of: $0) } ?? ""
            let rows = store.versions(of: entryID).compactMap { version -> VersionRow? in
                guard let text = store.text(of: version) else { return nil }
                return VersionRow(
                    version: version,
                    text: text,
                    words: VersionText.words(text),
                    isCurrent: VersionText.same(text, current)
                )
            }
            return (file?.startedAt, rows)
        }.value

        entryStartedAt = loaded.0
        rows = loaded.1
        if selected == nil {
            // Start on the newest version that differs from the entry as it reads now.
            selectedID = (rows.first { !$0.isCurrent } ?? rows.first)?.id
        }
        isLoading = false
    }

    /// For tests and pictures: show these versions without touching any files.
    func show(rows: [VersionRow], entryStartedAt: Date?, selecting selectedID: String? = nil) {
        self.rows = rows
        self.entryStartedAt = entryStartedAt
        self.selectedID = selectedID ?? (rows.first { !$0.isCurrent } ?? rows.first)?.id
        isLoading = false
    }

    /// Keeps the entry as it reads now, then hands back the chosen version's text for the page.
    /// Returns nil, changing nothing, if the entry could not be kept first.
    func restore() async -> String? {
        guard let row = selected, !row.isCurrent else { return nil }

        // Read the entry again: it may have been saved since the list was loaded.
        let journal = self.journal
        let entryID = self.entryID
        let current = await Task.detached(priority: .userInitiated) { () -> String in
            journal.entryFiles()?.first { $0.id == entryID }.flatMap { journal.text(of: $0) } ?? ""
        }.value

        guard await keep(current, entryID) else {
            note = "Couldn't keep the entry as it reads now, so nothing was restored."
            return nil
        }
        note = nil
        return VersionText.forPage(row.text)
    }
}

/// What ContentView places over the window.
struct VersionsView: View {
    @StateObject private var model: VersionsModel

    let fontName: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme
    let onRestore: (String) -> Void
    let onClose: () -> Void

    init(
        entryID: UUID,
        fontName: String,
        fontSize: CGFloat,
        colorScheme: ColorScheme,
        onRestore: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: VersionsModel(entryID: entryID))
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorScheme = colorScheme
        self.onRestore = onRestore
        self.onClose = onClose
    }

    var body: some View {
        VersionsScreen(
            model: model,
            style: MapStyle(fontName: fontName, isLight: colorScheme == .light),
            fontSize: fontSize,
            onRestore: {
                Task {
                    if let text = await model.restore() {
                        onRestore(text)
                    }
                }
            },
            onClose: onClose
        )
        .task {
            await model.load()
        }
        .onAppear {
            // Typing must not reach the page hidden underneath.
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

/// The screen itself: the version on the left, the list on the right, words along the bottom.
struct VersionsScreen: View {
    @ObservedObject var model: VersionsModel
    let style: MapStyle
    let fontSize: CGFloat
    let onRestore: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                style.backgroundColor

                if model.isLoading {
                    EmptyView()
                } else if let row = model.selected {
                    page(row)
                } else {
                    emptyState
                }

                VStack(spacing: 0) {
                    Spacer()
                    if let note = model.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }
                    bottomBar
                }
            }

            if !model.rows.isEmpty {
                Divider()
                list
                    .frame(width: 200)
            }
        }
        .background(style.backgroundColor)
    }

    // MARK: - The version, laid out like the page

    /// The same line spacing the page uses: one and a half times the font size.
    private var lineSpacing: CGFloat {
        let font = NSFont(name: style.fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        return (fontSize * 1.5) - NSLayoutManager().defaultLineHeight(for: font)
    }

    private func page(_ row: VersionRow) -> some View {
        ScrollView {
            Text(VersionText.forPage(row.text))
                .font(.custom(style.fontName, size: fontSize))
                .foregroundColor(style.bodyColor)
                .lineSpacing(lineSpacing)
                .textSelection(.enabled)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.top, 40)
                .padding(.bottom, 88)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        // A newly chosen version starts at its top.
        .id(row.id)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No earlier versions yet")
                .font(.custom(style.fontName, size: 18))
                .foregroundColor(style.bodyColor)
            Text("A copy is kept every five minutes while an entry changes.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - The words along the bottom

    private var bottomBar: some View {
        HStack(spacing: 8) {
            MapWord(title: "Close", style: style, action: onClose)
                .keyboardShortcut(.cancelAction)

            if let row = model.selected {
                Text("•").foregroundColor(.gray)
                if row.isCurrent {
                    Text("This is how the entry reads now")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    MapWord(title: "Restore this version", style: style, action: onRestore)
                }

                Spacer()

                Text("\(Prompts.longDay(row.version.savedAt)), \(VersionText.time(row.version.savedAt))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Spacer()
            }
        }
        .padding(8)
        .padding()
        .background(style.backgroundColor.opacity(0.9))
    }

    // MARK: - The list of versions, styled like History

    private var list: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Versions")
                    .font(.system(size: 13))
                    .foregroundColor(style.quietColor)
                if let started = model.entryStartedAt {
                    Text("Entry from \(VersionText.shortDay(started))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        VersionRowButton(row: row, isSelected: model.selectedID == row.id) {
                            model.selectedID = row.id
                        }
                        if row.id != model.rows.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .background(style.backgroundColor)
    }
}

/// One version in the list: its time, then its day and length.
private struct VersionRowButton: View {
    let row: VersionRow
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(VersionText.time(row.version.savedAt))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(VersionText.shortDay(row.version.savedAt)) · \(row.isCurrent ? "as it reads now" : VersionText.wordsLine(row.words))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.gray.opacity(0.1) : (isHovering ? Color.gray.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

/// The small icon in a History row that opens an entry's earlier versions.
/// It shows only for entries that have one, so with versions off the sidebar is freewrite's own.
struct VersionsIconButton: View {
    let entryID: UUID
    let isLight: Bool
    let action: () -> Void

    @ObservedObject private var index: VersionIndex
    @State private var isHovering = false

    init(
        entryID: UUID,
        isLight: Bool,
        index: VersionIndex = SnapshotKeeper.shared.index,
        action: @escaping () -> Void
    ) {
        self.entryID = entryID
        self.isLight = isLight
        self.index = index
        self.action = action
    }

    var body: some View {
        if index.entries.contains(entryID) {
            Button(action: action) {
                BarIcon(kind: .clock, size: 13)
                    .foregroundColor(isHovering ? (isLight ? .black : .white) : (isLight ? .gray : .gray.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .help("Earlier versions of this entry")
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}
