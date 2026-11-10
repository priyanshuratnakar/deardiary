//
//  MapDetailView.swift
//  Dear Diary
//
//  The panel beside the map. For a thought it shows what the AI understands
//  about it, how it has shifted, and the exact lines from the entries behind
//  it. For a link it shows why the two thoughts are connected and the lines
//  that show it. Clicking a day opens that entry.
//
//  Same quiet style as the talk column: no boxes, text in the page's font.
//

import SwiftUI

struct MapDetailView: View {
    @ObservedObject var model: MapModel
    let selection: MapSelection
    let style: MapStyle
    let onOpenEntry: (UUID) -> Void

    var body: some View {
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.never)
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

            if let seen = seenLine(detail) {
                Text(seen)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }

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
            section("What you wrote") {
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
            ? detail.kind.rawValue
            : "\(detail.kind.rawValue) · also \(detail.aliases.joined(separator: ", "))"
    }

    private func seenLine(_ detail: MapThoughtDetail) -> String? {
        guard let first = detail.firstSeen, let last = detail.lastSeen else { return nil }
        return first == last
            ? "Seen on \(Prompts.longDay(first))"
            : "First seen \(Prompts.longDay(first)) · last seen \(Prompts.longDay(last))"
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
            Text(detail.reasons.joined(separator: "; "))
                .font(.custom(style.fontName, size: 20))
                .foregroundColor(style.bodyColor)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !detail.days.isEmpty {
            section("What shows it") {
                days(detail.days)
            }
        }
    }

    // MARK: - Pieces

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
            }
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
