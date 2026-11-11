//
//  TalkController.swift
//  Dear Diary
//
//  The brain of talk mode. It decides when talk is available, turns it on and
//  off, builds each request from the entry and the conversation, and saves the
//  conversation next to the entry.
//
//  Nothing here runs unless the user has switched talk on. While it is off,
//  no request is ever made.
//
//  Three things are decided here, by the app, and not left to the model:
//
//  1. Never two questions in a row. If the last reply asked something and the
//     user has answered, the next reply is told not to ask (`Prompts.talkNoQuestionNote`).
//  2. The help line. If what was written may mean danger (`CareNet`), the app
//     shows its own line at once and tells the model to follow the danger rule.
//     If the model marks a reply as care by itself, the line is shown too.
//  3. Earlier lines are written out by the app (`TalkReply`), word for word.
//

import Foundation
import Combine

/// Limits for talk mode.
enum TalkLimits {
    /// When a model marks a reply as care, the help line is shown with it unless it is
    /// already among this many lines just above, so it is there without being repeated
    /// under every reply.
    static let careLineGap = 6
}

/// The entry talk mode is reading.
struct TalkEntry: Equatable {
    let id: UUID
    var text: String
    var date: Date?

    /// Reads the start time out of an entry filename such as
    /// "[6910BBDE-…]-[2026-11-10-21-42-07].md".
    static func date(fromFilename filename: String?) -> Date? {
        guard let filename,
              filename.hasSuffix("].md"),
              let divider = filename.range(of: "]-[") else {
            return nil
        }
        let stamp = filename[divider.upperBound..<filename.index(filename.endIndex, offsetBy: -4)]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.date(from: String(stamp))
    }
}

/// What the talk column shows. It changes often while a reply streams in, so it
/// is kept apart from `TalkController`; that way only the column redraws, not the page.
@MainActor
final class TalkTranscript: ObservableObject {
    /// The saved conversation for the current entry, oldest first.
    @Published fileprivate(set) var messages: [TalkMessage] = []
    /// The reply being written right now, if any.
    @Published fileprivate(set) var replyInProgress: String? = nil
    /// True after a message is sent and before the first words come back.
    @Published fileprivate(set) var isWaiting = false
    /// A small, plain message when something went wrong.
    @Published fileprivate(set) var notice: String? = nil
    /// True when "Try again" makes sense.
    @Published fileprivate(set) var canRetry = false

    var isBusy: Bool {
        isWaiting || replyInProgress != nil
    }
}

@MainActor
final class TalkController: ObservableObject {
    /// True when AI is on and the chosen service is set up. The Talk word only shows then.
    @Published private(set) var isAvailable = false
    /// True while the talk column is open.
    @Published private(set) var isOn = false

    let transcript = TalkTranscript()

    private let settings: AISettings
    private let store: ConversationStore
    private let memoryStore: MemoryStore
    private let makeProvider: () -> LLMProvider
    private let now: () -> Date
    private let talkSwitchedOn: () -> Void

    private var entry: TalkEntry? = nil
    /// Set when the user switches talk on, and used once: talk only speaks first at that moment.
    private var shouldSpeakFirst = false
    /// The reply being fetched. Tests wait on this.
    private(set) var replyTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: AISettings = .shared,
        store: ConversationStore = ConversationStore(),
        memoryStore: MemoryStore = MemoryStore(),
        now: @escaping () -> Date = { Date() },
        provider: @escaping () -> LLMProvider = { AIRouter.shared },
        talkSwitchedOn: @escaping () -> Void = { MemoryEngine.shared.nudge(includeFresh: true) }
    ) {
        self.settings = settings
        self.store = store
        self.memoryStore = memoryStore
        self.now = now
        self.makeProvider = provider
        self.talkSwitchedOn = talkSwitchedOn
        self.isAvailable = settings.isReady

        settings.readiness
            .sink { [weak self] available in
                self?.availabilityChanged(available)
            }
            .store(in: &cancellables)
    }

    // MARK: - On and off

    /// The Talk word in the bottom bar was clicked.
    func toggle() {
        if isOn {
            turnOff()
        } else if isAvailable {
            shouldSpeakFirst = true
            isOn = true
            // Turning talk on is one of the moments an entry counts as settled for memory.
            talkSwitchedOn()
        }
    }

    /// Closes the column and stops any reply that is on its way.
    func turnOff() {
        cancelReply()
        shouldSpeakFirst = false
        isOn = false
    }

    private func availabilityChanged(_ available: Bool) {
        isAvailable = available
        if !available {
            turnOff()
        }
    }

    // MARK: - Following the page

    /// Called when the column appears and when a different entry is selected.
    /// Loads that entry's conversation. Talk speaks first only if the user has
    /// just switched it on, the page has writing, and nothing was said before.
    func show(entry newEntry: TalkEntry?) {
        let speakFirst = shouldSpeakFirst
        shouldSpeakFirst = false

        guard isOn else { return }

        cancelReply()
        entry = newEntry
        transcript.notice = nil
        transcript.canRetry = false
        transcript.messages = newEntry.map { store.load(entryID: $0.id) } ?? []

        if speakFirst,
           let newEntry,
           !transcript.messages.contains(where: { $0.speaker != .note }),
           !newEntry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showCareLineIfNeeded(entry: newEntry)
            requestReply()
        }
    }

    /// Keeps the entry text current while the user writes. Nothing is redrawn and nothing is sent.
    func entryTextChanged(_ text: String) {
        entry?.text = text
    }

    /// An entry was deleted from history: its conversation goes with it.
    func entryDeleted(_ entryID: UUID) {
        if entry?.id == entryID {
            cancelReply()
            entry = nil
            transcript.messages = []
            transcript.notice = nil
            transcript.canRetry = false
        }
        store.delete(entryID: entryID)
    }

    // MARK: - Talking

    /// Sends what the user typed in the column.
    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isOn, isAvailable, !transcript.isBusy, !text.isEmpty, let entry else {
            return
        }

        transcript.messages.append(TalkMessage(speaker: .you, text: text, date: now()))
        showCareLineIfNeeded(entry: entry)
        store.save(transcript.messages, entryID: entry.id)
        requestReply()
    }

    /// Shows the app's help line, at once, if what was just written may mean danger:
    /// the message just sent, or the entry if this conversation has not shown the line yet.
    /// It does not wait for a reply, so the line is there even if no reply ever comes.
    private func showCareLineIfNeeded(entry: TalkEntry) {
        let waiting = Self.sinceLastReply(transcript.messages)
        guard !waiting.contains(where: { $0.speaker == .note }) else { return }

        let inAMessage = waiting.contains { $0.speaker == .you && CareNet.mayBeInDanger($0.text) }
        let inTheEntry = !transcript.messages.contains(where: { $0.speaker == .note }) && CareNet.mayBeInDanger(entry.text)
        guard inAMessage || inTheEntry else { return }

        transcript.messages.append(TalkMessage(speaker: .note, text: Prompts.talkCareLine, date: now()))
        store.save(transcript.messages, entryID: entry.id)
    }

    /// Asks again after a failed reply.
    func retry() {
        guard transcript.canRetry, !transcript.isBusy else { return }
        requestReply()
    }

    private func requestReply() {
        guard isOn, isAvailable, let entry else { return }

        transcript.notice = nil
        transcript.canRetry = false
        transcript.replyInProgress = nil
        transcript.isWaiting = true

        let model = settings.resolvedTalkModel
        let messages = transcript.messages
        let turn = Self.turn(for: messages)
        let recentMessages = messages.filter { $0.speaker == .you }.suffix(4).map(\.text)
        let entryID = entry.id
        let provider = makeProvider()

        replyTask = Task { [weak self] in
            // If talk was switched off before this even started, send nothing at all.
            guard !Task.isCancelled else { return }

            // Pick the lines from memory that bear on this, if memory is on. When someone
            // may be in danger nothing from memory is sent: that reply is about now.
            var memory: TalkMemoryContext? = nil
            if turn != .danger {
                memory = await self?.memoryContext(for: entry, recentMessages: recentMessages)
            }
            guard self != nil, !Task.isCancelled else { return }
            let lines = Prompts.earlierLines(from: memory)

            let request = LLMRequest(
                model: model,
                system: Prompts.talkSystem(entryText: entry.text, entryDate: entry.date, memory: memory, turn: turn),
                messages: Self.history(from: messages, lines: lines),
                maxTokens: AILimits.talkMaxTokens,
                retryIfDeclined: true
            )

            var reply = ""
            do {
                for try await piece in provider.stream(request) {
                    reply += piece
                    guard let self, !Task.isCancelled else { return }
                    // What is shown is the reply with the app's parts filled in: an earlier
                    // line written out, the private care mark taken off.
                    let shown = TalkReply.shown(reply, lines: lines, finished: false).text
                    if !shown.isEmpty {
                        self.transcript.isWaiting = false
                        self.transcript.replyInProgress = shown
                    }
                }
                guard let self, !Task.isCancelled else { return }
                self.finishReply(reply, lines: lines, entryID: entryID)
            } catch is CancellationError {
                // Talk was switched off or the entry changed. The partial reply is dropped.
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.failReply(error)
            }
        }
    }

    /// The notes from memory to send with a reply, or nil when memory is off or empty.
    /// The files are read off the main thread, so typing is never held up.
    private func memoryContext(for entry: TalkEntry, recentMessages: [String]) async -> TalkMemoryContext? {
        guard settings.memoryAllowed() else { return nil }
        let store = memoryStore
        let context = await Task.detached(priority: .userInitiated) {
            ContextBuilder.build(
                entry: entry,
                recentMessages: recentMessages,
                memory: store.loadSnapshot(),
                digests: store.loadAllDigests()
            )
        }.value
        return context.isEmpty ? nil : context
    }

    private func finishReply(_ reply: String, lines: [EarlierLine], entryID: UUID) {
        clearReplyState()
        guard entry?.id == entryID else { return }

        let shown = TalkReply.shown(reply, lines: lines, finished: true)
        guard !shown.text.isEmpty else {
            transcript.notice = "\(settings.provider.serviceName) answered with nothing."
            transcript.canRetry = true
            return
        }

        // The model saw danger that the app's own net did not: show the help line with
        // this reply, unless it has been shown in the last few lines already.
        let showedLately = transcript.messages.suffix(TalkLimits.careLineGap).contains { $0.speaker == .note }
        if (shown.flaggedCare || TalkReply.asksIfSafe(shown.text)), !showedLately {
            transcript.messages.append(TalkMessage(speaker: .note, text: Prompts.talkCareLine, date: now()))
        }

        transcript.messages.append(TalkMessage(speaker: .diary, text: shown.text, date: now()))
        store.save(transcript.messages, entryID: entryID)
    }

    private func failReply(_ error: Error) {
        clearReplyState()
        let known = (error as? LLMError) ?? .unexpected
        // A declined reply shows the support options too, in case the entry was a hard one.
        transcript.notice = known == .refused
            ? Prompts.talkDeclined(by: settings.provider)
            : known.userMessage(for: settings.provider)
        transcript.canRetry = true
    }

    private func cancelReply() {
        replyTask?.cancel()
        clearReplyState()
    }

    private func clearReplyState() {
        replyTask = nil
        transcript.isWaiting = false
        transcript.replyInProgress = nil
    }

    // MARK: - Building the conversation for the model

    /// What has been said since the last reply: the messages still waiting for one.
    static func sinceLastReply(_ messages: [TalkMessage]) -> [TalkMessage] {
        guard let lastReply = messages.lastIndex(where: { $0.speaker == .diary }) else { return messages }
        return Array(messages[(lastReply + 1)...])
    }

    /// What the app adds to the instructions for the next reply.
    static func turn(for messages: [TalkMessage]) -> Prompts.TalkTurn {
        let waiting = sinceLastReply(messages)

        // The help line is showing and has not been answered, or a message may mean danger.
        if waiting.contains(where: { $0.speaker == .note || ($0.speaker == .you && CareNet.mayBeInDanger($0.text)) }) {
            return .danger
        }

        // Never two questions in a row: the last reply asked, and they have answered.
        guard let lastReply = messages.lastIndex(where: { $0.speaker == .diary }) else { return .ordinary }
        let answer = waiting.filter { $0.speaker == .you }.map(\.text).joined(separator: "\n")
        // A reply that came with the help line is left alone: the danger rule covers what follows it.
        let cameWithHelpLine = lastReply > 0 && messages[lastReply - 1].speaker == .note
        if !answer.isEmpty,
           // If they asked something instead of answering, the reply should answer it.
           !TalkReply.writerAsks(answer),
           !cameWithHelpLine,
           TalkReply.asksAQuestion(messages[lastReply].text) {
            return .noQuestion
        }
        return .ordinary
    }

    /// Turns the saved conversation into the back-and-forth the model expects:
    /// it must start with the user, and the two sides must take turns.
    ///
    /// The app's own help line is left out: no model wrote it and none is sent it. An
    /// earlier line the app wrote out goes back to its number (see `TalkReply.forModel`),
    /// and a reply that came with the help line gets its care mark back, so the model
    /// sees its own replies the way it is asked to write them.
    static func history(from messages: [TalkMessage], lines: [EarlierLine] = []) -> [LLMMessage] {
        var result: [LLMMessage] = []
        for (index, original) in messages.enumerated() {
            guard original.speaker != .note else { continue }
            var message = original
            if message.speaker == .diary {
                message.text = TalkReply.forModel(message.text, lines: lines)
                guard !message.text.isEmpty else { continue }
                if index > 0, messages[index - 1].speaker == .note {
                    message.text = TalkReply.careTag + "\n" + message.text
                }
            }
            let role: LLMMessage.Role = message.speaker == .you ? .user : .assistant
            if let last = result.last, last.role == role {
                // Two in a row from the same side (for example after a failed reply) are joined.
                result[result.count - 1] = LLMMessage(role: role, text: last.text + "\n\n" + message.text)
            } else {
                result.append(LLMMessage(role: role, text: message.text))
            }
        }
        // When talk spoke first there is no user line before its reply,
        // so put back the unseen opening line it was answering.
        if result.first?.role != .user {
            result.insert(LLMMessage(role: .user, text: Prompts.talkOpener), at: 0)
        }
        return result
    }
}
