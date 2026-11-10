//
//  TalkTestSupport.swift
//  freewriteTests
//
//  Helpers for the talk mode tests: a pretend AI that replies from a script,
//  throwaway storage, and a way to draw a view off screen.
//  The entries and conversations used here are made up.
//

import XCTest
import SwiftUI
@testable import freewrite

/// A pretend AI. It answers from a script and remembers what it was asked,
/// so tests can check exactly what would have been sent. It never uses the network.
final class FakeProvider: LLMProvider, @unchecked Sendable {
    enum Step {
        /// Reply with these pieces, one after another.
        case reply([String])
        /// Fail with this error.
        case fail(LLMError)
        /// Reply with some pieces, then fail.
        case replyThenFail([String], LLMError)
        /// Never answer (until the request is cancelled).
        case hang
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var seen: [LLMRequest] = []

    init(_ steps: [Step] = []) {
        self.steps = steps
    }

    /// Every request made so far, in order.
    var requests: [LLMRequest] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    private func nextStep(for request: LLMRequest) -> Step {
        lock.lock()
        defer { lock.unlock() }
        seen.append(request)
        return steps.isEmpty ? .reply(["(no scripted reply)"]) : steps.removeFirst()
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        let step = nextStep(for: request)
        return AsyncThrowingStream { continuation in
            switch step {
            case .reply(let pieces):
                pieces.forEach { continuation.yield($0) }
                continuation.finish()
            case .fail(let error):
                continuation.finish(throwing: error)
            case .replyThenFail(let pieces, let error):
                pieces.forEach { continuation.yield($0) }
                continuation.finish(throwing: error)
            case .hang:
                break
            }
        }
    }

    func complete(_ request: LLMRequest) async throws -> LLMReply {
        switch nextStep(for: request) {
        case .reply(let pieces):
            return LLMReply(text: pieces.joined(), inputTokens: 1200, outputTokens: 300)
        case .fail(let error), .replyThenFail(_, let error):
            throw error
        case .hang:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return LLMReply(text: "")
        }
    }
}

/// Everything talk mode needs, backed by storage that exists only for one test.
@MainActor
final class TalkSandbox {
    let root: URL
    let settings: AISettings
    let store: ConversationStore

    private let suiteName = "deardiary.tests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let keychain: Keychain

    /// Dates handed out to new messages: one second apart, starting at a fixed moment.
    private var clock = Date(timeIntervalSince1970: 1_794_000_000)

    init(aiOn: Bool = true, hasKey: Bool = true) {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Freewrite", isDirectory: true)
        defaults = UserDefaults(suiteName: suiteName)!
        keychain = Keychain(service: "com.priyanshuratnakar.deardiary.tests.\(UUID().uuidString)", account: "test")
        settings = AISettings(defaults: defaults, keychain: keychain)
        store = ConversationStore(root: root)

        settings.aiEnabled = aiOn
        if hasKey {
            settings.saveAPIKey("made-up-key-for-tests")
        }
        settings.talkModel = "model-for-talk"
    }

    func controller(_ provider: FakeProvider) -> TalkController {
        TalkController(
            settings: settings,
            store: store,
            now: { [unowned self] in self.tick() },
            provider: { provider },
            talkSwitchedOn: {}
        )
    }

    func tick() -> Date {
        clock = clock.addingTimeInterval(1)
        return clock
    }

    deinit {
        keychain.delete()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }
}

/// Waits (briefly) until something becomes true, for work that starts a moment later.
@MainActor
func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

/// Made-up journal content for tests.
enum TalkFixtures {
    static let entryID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let otherEntryID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    static let entryText = """
    Couldn't sleep again. I keep replaying the call with Meera about the launch. \
    I said yes to everything she asked and then felt sick about it for the rest of the day.
    """

    static var entry: TalkEntry {
        TalkEntry(id: entryID, text: entryText, date: Date(timeIntervalSince1970: 1_793_990_000))
    }

    static var emptyEntry: TalkEntry {
        TalkEntry(id: entryID, text: "\n\n   ", date: nil)
    }

    static func conversation() -> [TalkMessage] {
        let start = Date(timeIntervalSince1970: 1_793_995_000)
        return [
            TalkMessage(speaker: .diary, text: "You said yes to everything and then felt sick for the rest of the day. What were you afraid would happen if you had said no to even one thing?", date: start),
            TalkMessage(speaker: .you, text: "That she'd think I can't handle it.", date: start.addingTimeInterval(40)),
            TalkMessage(speaker: .diary, text: "So the yes was protecting how she sees you. And the sick feeling came afterwards, when you were alone with it. What do you think that feeling was trying to tell you?", date: start.addingTimeInterval(55)),
        ]
    }
}

/// Draws a SwiftUI view off screen and returns the picture.
@MainActor
func renderOffscreen<Content: View>(_ view: Content, size: CGSize? = nil, dark: Bool) throws -> NSImage {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size ?? hosting.fittingSize)

    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    // Give SwiftUI one turn of the run loop to finish laying out (scroll views need it).
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    hosting.layoutSubtreeIfNeeded()

    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    XCTAssertGreaterThan(bitmap.pixelsWide, 0)
    XCTAssertGreaterThan(bitmap.pixelsHigh, 0)

    let image = NSImage(size: hosting.bounds.size)
    image.addRepresentation(bitmap)
    return image
}

extension XCTestCase {
    /// Attaches a picture to the test results so it can be looked at afterwards.
    func attach(_ image: NSImage, named name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
