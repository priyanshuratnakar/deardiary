//
//  MapDetailView.swift
//  Dear Diary
//
//  The panel beside the map. For a thought it shows what the AI understands
//  about it, how it has shifted, and the exact lines from the entries behind
//  it. For a link it shows why the two thoughts are connected and the lines
//  that show it. Clicking a day opens that entry.
//
//  Along the bottom of the panel, always in view, are the user's fixes:
//  rename, merge, link, delete, and remove link. Anything that cannot be
//  undone here asks for a second click.
//
//  Same quiet style as the talk column: no boxes, text in the page's font.
//

import SwiftUI

struct MapDetailView: View {
    @ObservedObject var model: MapModel
    let selection: MapSelection
    let style: MapStyle
    let onOpenEntry: (UUID) -> Void

    /// What is being typed for a rename or a link's reason.
    @State private var draft = ""
    /// True while the line being typed in has the keyboard.
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selection {
                    case .thought(let id):
                        if let detail = model.thoughtDetail(id) {
                            thought(detail)
                        }
                    case .link(let id):
                        if let detail = model.linkDetail(id) {
                            link(detail)
                        }
                    case .day(let entryID):
                        if let detail = model.dayDetail(entryID) {
                            day(detail)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)

            // The fixes stay in view however long the panel is.
            VStack(alignment: .leading, spacing: 8) {
                switch selection {
                case .thought(let id):
                    if let detail = model.thoughtDetail(id) {
                        thoughtFixes(detail)
                    }
                case .link(let id):
                    if let detail = model.linkDetail(id) {
                        linkFixes(detail)
                    }
                case .day(let entryID):
                    // A day is your own writing, so there is nothing to fix: only a way to read it.
                    MapWord(title: "Open this entry", style: style) {
                        onOpenEntry(entryID)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(style.backgroundColor)
    }

    // MARK: - A thought

    @ViewBuilder
    private func thought(_ detail: MapThoughtDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.label)
                .font(.custom(style.fontName, size: 20))
                .foregroundColor(style.bodyColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Circle()
                    .fill(style.color(for: detail.kind))
                    .frame(width: 8, height: 8)
                Text(kindLine(detail))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }

        // What the app can say by counting. No model writes these lines.
        if !detail.counted.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(detail.counted, id: \.self) { line in
                    paragraph(line)
                }
            }
        }

        // A description in the AI's words: only a thought from before M14 has one.
        if !detail.summary.isEmpty {
            paragraph(detail.summary)
        }

        if !detail.shifts.isEmpty {
            section("How it has shifted") {
                ForEach(Array(detail.shifts.enumerated()), id: \.offset) { _, shift in
                    VStack(alignment: .leading, spacing: 2) {
                        small(Prompts.longDay(shift.date))
                        paragraph(shift.note)
                    }
                }
            }
        }

        if !detail.days.isEmpty {
            section(detail.days.count == 1 ? "On that day" : "On those days") {
                days(detail.days)
            }
        }

        if !detail.connections.isEmpty {
            section("Linked to") {
                ForEach(detail.connections) { connection in
                    VStack(alignment: .leading, spacing: 2) {
                        MapWord(title: connection.label, style: style) {
                            model.selection = .link(connection.linkID)
                        }
                        small(connection.reasons.joined(separator: "; "))
                    }
                }
            }
        }
    }

    private func kindLine(_ detail: MapThoughtDetail) -> String {
        detail.aliases.isEmpty
            ? detail.kind.name
            : "\(detail.kind.name) · also \(detail.aliases.joined(separator: ", "))"
    }

    // MARK: - Fixes for a thought

    @ViewBuilder
    private func thoughtFixes(_ detail: MapThoughtDetail) -> some View {
        switch model.pending {
        case .renaming(let id) where id == detail.id:
            typed(
                prompt: "A new name",
                confirm: "Save",
                onConfirm: { run(.rename(id: detail.id, to: draft)) }
            )

        case .pickingMergeTarget(let source) where source == detail.id:
            waiting("Click the thought to fold this one into.")

        case .confirmingMerge(let source, let target) where source == detail.id:
            confirmation(
                "Fold “\(detail.label)” into “\(model.label(of: target))”? Its lines, links and names move over. This cannot be undone here.",
                confirm: "Merge",
                onConfirm: { run(.merge(from: source, into: target)) }
            )

        case .pickingLinkTarget(let source) where source == detail.id:
            waiting("Click the thought to link this one to.")

        case .reasonForLink(let source, let target) where source == detail.id:
            VStack(alignment: .leading, spacing: 8) {
                small("How are “\(detail.label)” and “\(model.label(of: target))” linked?")
                typed(
                    prompt: "A few words, such as: helps with",
                    confirm: "Add link",
                    onConfirm: { run(.addLink(from: source, to: target, reason: draft)) }
                )
            }

        case .confirmingDelete(let id) where id == detail.id:
            confirmation(
                "Delete “\(detail.label)”? It is removed from memory and the AI will not bring it back. Your entries are not touched.",
                confirm: "Delete",
                onConfirm: { run(.delete(id: detail.id)) }
            )

        case .confirmingSettle(let id, let how) where id == detail.id:
            confirmation(
                how == .done
                    ? "Mark this as done? It leaves the map. The line stays on its day, marked done."
                    : "Not doing this after all? It leaves the map. The line stays on its day.",
                confirm: how == .done ? "Done" : "Not doing it",
                onConfirm: { run(.settle(id: detail.id, as: how, on: MemoryText.day(Date()))) }
            )

        default:
            if detail.kind == .open {
                // Something still open is closed by the writer, not folded into something else.
                HStack(spacing: 8) {
                    MapWord(title: "Done", style: style) {
                        model.pending = .confirmingSettle(detail.id, .done)
                    }
                    Text("•").foregroundColor(.gray)
                    MapWord(title: "Not doing it", style: style) {
                        model.pending = .confirmingSettle(detail.id, .dropped)
                    }
                    Text("•").foregroundColor(.gray)
                    MapWord(title: "Rename", style: style) {
                        draft = detail.label
                        model.pending = .renaming(detail.id)
                    }
                    Text("•").foregroundColor(.gray)
                    MapWord(title: "Delete", style: style) {
                        model.pending = .confirmingDelete(detail.id)
                    }
                }
            } else {
                ordinaryFixes(detail)
            }
        }
    }

    private func ordinaryFixes(_ detail: MapThoughtDetail) -> some View {
            HStack(spacing: 8) {
                MapWord(title: "Rename", style: style) {
                    draft = detail.label
                    model.pending = .renaming(detail.id)
                }
                Text("•").foregroundColor(.gray)
                MapWord(title: "Merge into…", style: style) {
                    model.pending = .pickingMergeTarget(source: detail.id)
                }
                Text("•").foregroundColor(.gray)
                MapWord(title: "Link to…", style: style) {
                    draft = ""
                    model.pending = .pickingLinkTarget(source: detail.id)
                }
                Text("•").foregroundColor(.gray)
                MapWord(title: "Delete", style: style) {
                    model.pending = .confirmingDelete(detail.id)
                }
            }
    }

    // MARK: - A link

    @ViewBuilder
    private func link(_ detail: MapLinkDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                MapWord(title: detail.firstLabel, style: style) {
                    model.selection = .thought(detail.firstID)
                }
                Text("and").font(.system(size: 13)).foregroundColor(.secondary)
                MapWord(title: detail.secondLabel, style: style) {
                    model.selection = .thought(detail.secondID)
                }
            }
            Text(detail.reasons.isEmpty ? "linked" : detail.reasons.joined(separator: "; "))
                .font(.custom(style.fontName, size: 20))
                .foregroundColor(style.bodyColor)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !detail.linkedByYou.isEmpty {
            small("Linked by you. There is no quoted line behind this.")
        }

        if !detail.days.isEmpty {
            section("What shows it") {
                days(detail.days)
            }
        }
    }

    // MARK: - Fixes for a link

    @ViewBuilder
    private func linkFixes(_ detail: MapLinkDetail) -> some View {
        if model.pending == .confirmingRemoveLink(detail.id) {
            confirmation(
                "Remove the link between “\(detail.firstLabel)” and “\(detail.secondLabel)”? The AI will not put it back.",
                confirm: "Remove",
                onConfirm: { run(.removeLink(detail.firstID, detail.secondID)) }
            )
        } else {
            MapWord(title: "Remove link", style: style) {
                model.pending = .confirmingRemoveLink(detail.id)
            }
        }
    }

    // MARK: - A day

    @ViewBuilder
    private func day(_ detail: MapDayDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Prompts.longDay(detail.date))
                .font(.custom(style.fontName, size: 20))
                .foregroundColor(style.bodyColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Circle()
                    .fill(style.dayColor)
                    .frame(width: 8, height: 8)
                small(detail.thoughts.isEmpty ? "day" : "day · touched \(detail.thoughts.count) \(detail.thoughts.count == 1 ? "thought" : "thoughts")")
            }
        }

        // What the AI noted about the entry as a whole: only an entry read before M14 has this.
        if let summary = detail.summary, !summary.isEmpty {
            paragraph(summary)
        }

        if !detail.lines.isEmpty {
            section("In your words") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(detail.lines.enumerated()), id: \.offset) { _, line in
                        tagged(line)
                    }
                }
            }
        }

        if !detail.thoughts.isEmpty {
            section("What it touched") {
                ForEach(detail.thoughts) { touched in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(style.color(for: touched.kind))
                                .frame(width: 8, height: 8)
                            MapWord(title: touched.label, style: style) {
                                model.selection = .thought(touched.thoughtID)
                            }
                        }
                        ForEach(Array(touched.quotes.enumerated()), id: \.offset) { _, quote in
                            paragraph("“\(quote)”")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func run(_ fix: MemoryFix) {
        Task { await model.perform(fix) }
    }

    /// A line of instruction while the app waits for a click on the map.
    private func waiting(_ instruction: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            paragraph(instruction)
            MapWord(title: "Cancel", style: style) {
                model.pending = nil
            }
        }
    }

    /// A question asked in place, with a word to go ahead and a word to back out.
    private func confirmation(_ question: String, confirm: String, onConfirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            paragraph(question)
            HStack(spacing: 8) {
                MapWord(title: confirm, style: style, action: onConfirm)
                Text("•").foregroundColor(.gray)
                MapWord(title: "Cancel", style: style) {
                    model.pending = nil
                }
            }
        }
    }

    /// A line to type in, with a word to save and a word to back out. Return also saves.
    private func typed(prompt: String, confirm: String, onConfirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                prompt,
                text: $draft,
                prompt: Text(prompt).foregroundColor(style.isLight ? .gray.opacity(0.5) : .gray.opacity(0.6))
            )
            .textFieldStyle(.plain)
            .font(.custom(style.fontName, size: 14))
            .foregroundColor(style.bodyColor)
            .focused($isTyping)
            .onAppear { isTyping = true }
            .onSubmit {
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onConfirm()
                }
            }

            HStack(spacing: 8) {
                MapWord(title: confirm, style: style) {
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onConfirm()
                    }
                }
                Text("•").foregroundColor(.gray)
                MapWord(title: "Cancel", style: style) {
                    model.pending = nil
                }
            }
        }
    }

    /// Quoted lines, grouped under the day they were written. The day opens the entry.
    private func days(_ days: [MapDayQuotes]) -> some View {
        ForEach(days) { day in
            VStack(alignment: .leading, spacing: 4) {
                MapWord(title: Prompts.longDay(day.date), style: style) {
                    onOpenEntry(day.entryID)
                }
                .help("Open this entry")

                ForEach(Array(day.quotes.enumerated()), id: \.offset) { _, quote in
                    paragraph("“\(quote)”")
                }
                ForEach(Array(day.lines.enumerated()), id: \.offset) { _, line in
                    tagged(line)
                }
            }
        }
    }

    /// One of the writer's own lines with the small word that says what it is: felt, told
    /// yourself, wanted. A feeling also says whether it was pleasant.
    private func tagged(_ line: MapTaggedLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.tag)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 74, alignment: .leading)
            (Text("“\(line.quote)”")
                .font(.custom(style.fontName, size: 14))
                .foregroundColor(style.bodyColor)
             + Text(line.note.map { "  " + $0 } ?? "")
                .font(.system(size: 11))
                .foregroundColor(.secondary))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            small(title)
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.custom(style.fontName, size: 14))
            .foregroundColor(style.bodyColor)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func small(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
