//
//  ConversationStore.swift
//  Dear Diary
//
//  Saves each entry's talk conversation as a small, readable markdown file:
//
//      <journal folder>/conversations/[ENTRY-UUID].md
//
//  The file can be opened, edited or deleted by hand. Deleting it loses the
//  conversation and nothing else.
//

import Foundation

/// One line of a talk conversation.
struct TalkMessage: Equatable {
    enum Speaker: String {
        case you = "You"
        case diary = "Dear Diary"
    }

    let speaker: Speaker
    var text: String
    let date: Date
}

struct ConversationStore {
    /// The journal folder. Tests pass a throwaway folder.
    let root: URL

    init(root: URL = StorageRoot.url) {
        self.root = root
    }

    var folder: URL {
        root.appendingPathComponent("conversations", isDirectory: true)
    }

    func fileURL(for entryID: UUID) -> URL {
        folder.appendingPathComponent("[\(entryID.uuidString)].md")
    }

    /// The saved conversation for an entry, oldest first. Empty if there is none.
    func load(entryID: UUID) -> [TalkMessage] {
        guard let content = try? String(contentsOf: fileURL(for: entryID), encoding: .utf8) else {
            return []
        }
        return Self.parse(content)
    }

    /// Saves the conversation, replacing what was there. An empty conversation removes the file.
    @discardableResult
    func save(_ messages: [TalkMessage], entryID: UUID) -> Bool {
        guard !messages.isEmpty else {
            return delete(entryID: entryID)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.render(messages).write(to: fileURL(for: entryID), atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Removes an entry's conversation. Returns true if it is gone afterwards.
    @discardableResult
    func delete(entryID: UUID) -> Bool {
        let url = fileURL(for: entryID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return true
        }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    // MARK: - File format

    private static let title = "# Talk"
    private static let separator = " · "

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func render(_ messages: [TalkMessage]) -> String {
        var lines: [String] = [title, ""]
        for message in messages {
            lines.append("## \(message.speaker.rawValue)\(separator)\(timestampFormatter.string(from: message.date))")
            lines.append("")
            for line in message.text.components(separatedBy: "\n") {
                // A line that looks like one of our headings is written with a
                // leading backslash so it is read back as ordinary text.
                lines.append(heading(from: line) != nil || isEscapedHeadingLike(line) ? "\\" + line : line)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func parse(_ content: String) -> [TalkMessage] {
        var messages: [TalkMessage] = []
        var current: (speaker: TalkMessage.Speaker, date: Date, lines: [String])? = nil

        func finishCurrent() {
            guard let finished = current else { return }
            let text = finished.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                messages.append(TalkMessage(speaker: finished.speaker, text: text, date: finished.date))
            }
            current = nil
        }

        for line in content.components(separatedBy: "\n") {
            if let heading = heading(from: line) {
                finishCurrent()
                current = (heading.speaker, heading.date, [])
            } else if current != nil {
                current?.lines.append(isEscapedHeadingLike(line) ? String(line.dropFirst()) : line)
            }
        }
        finishCurrent()
        return messages
    }

    /// True for a line that is one or more backslashes followed by "## ".
    /// Saving adds one backslash to such lines and loading removes one, so any text survives a round trip.
    private static func isEscapedHeadingLike(_ line: String) -> Bool {
        let withoutBackslashes = line.drop(while: { $0 == "\\" })
        return withoutBackslashes.count < line.count && withoutBackslashes.hasPrefix("## ")
    }

    /// Reads a line such as "## You · 2026-11-10 21:42:07".
    private static func heading(from line: String) -> (speaker: TalkMessage.Speaker, date: Date)? {
        guard line.hasPrefix("## ") else { return nil }
        let parts = line.dropFirst(3).components(separatedBy: separator)
        guard parts.count == 2,
              let speaker = TalkMessage.Speaker(rawValue: parts[0]),
              let date = timestampFormatter.date(from: parts[1]) else {
            return nil
        }
        return (speaker, date)
    }
}
