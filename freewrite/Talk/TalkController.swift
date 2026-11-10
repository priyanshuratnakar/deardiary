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

import Foundation
import Combine

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
           transcript.messages.isEmpty,
           !newEntry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        store.save(transcript.messages, entryID: entry.id)
        requestReply()
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
        let history = Self.history(from: transcript.messages)
        let recentMessages = transcript.messages.filter { $0.speaker == .you }.suffix(4).map(\.text)
        let entryID = entry.id
        let provider = makeProvider()

        replyTask = Task { [weak self] in
            // If talk was switched off before this even started, send nothing at all.
            guard !Task.isCancelled else { return }

            // Pick the notes from memory that bear on this, if memory is on.
            let memory = await self?.memoryContext(for: entry, recentMessages: recentMessages)
            guard self != nil, !Task.isCancelled else { return }

            let request = LLMRequest(
                model: model,
                system: Prompts.talkSystem(entryText: entry.text, entryDate: entry.date, memory: memory),
                messages: history,
                maxTokens: AILimits.talkMaxTokens,
                retryIfDeclined: true
            )

            var reply = ""
            do {
                for try await piece in provider.stream(request) {
                    reply += piece
                    guard let self, !Task.isCancelled else { return }
                    self.transcript.isWaiting = false
                    self.transcript.replyInProgress = reply
                }
                guard let self, !Task.isCancelled else { return }
                self.finishReply(reply, entryID: entryID)
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

    private func finishReply(_ reply: String, entryID: UUID) {
        clearReplyState()
        guard entry?.id == entryID else { return }

        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            transcript.notice = "\(settings.provider.serviceName) answered with nothing."
            transcript.canRetry = true
            return
        }

        transcript.messages.append(TalkMessage(speaker: .diary, text: text, date: now()))
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

    /// Turns the saved conversation into the back-and-forth the model expects:
    /// it must start with the user, and the two sides must take turns.
    static func history(from messages: [TalkMessage]) -> [LLMMessage] {
        var result: [LLMMessage] = []
        for message in messages {
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
