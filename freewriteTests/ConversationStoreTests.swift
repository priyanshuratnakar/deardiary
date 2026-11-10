//
//  ConversationStoreTests.swift
//  freewriteTests
//
//  Checks that talk conversations are saved as readable markdown next to the
//  journal and read back exactly. Uses a throwaway folder and made-up text.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct ConversationStoreTests {

    /// A store in a folder that exists only for one test.
    private final class Sandbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Freewrite", isDirectory: true)

        var store: ConversationStore { ConversationStore(root: root) }

        deinit {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
    }

    private let entryID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let start = Date(timeIntervalSince1970: 1_794_000_000)

    private func sample() -> [TalkMessage] {
        [
            TalkMessage(speaker: .diary, text: "What were you afraid would happen?", date: start),
            TalkMessage(speaker: .you, text: "That she'd think I can't handle it.", date: start.addingTimeInterval(40)),
            TalkMessage(speaker: .diary, text: "So the yes was protecting how she sees you.", date: start.addingTimeInterval(55)),
        ]
    }

    @Test func savesAndReadsBackExactly() {
        let sandbox = Sandbox()

        #expect(sandbox.store.save(sample(), entryID: entryID))
        #expect(sandbox.store.load(entryID: entryID) == sample())
    }

    @Test func fileLivesInConversationsFolderNamedAfterTheEntry() {
        let sandbox = Sandbox()
        sandbox.store.save(sample(), entryID: entryID)

        let expected = sandbox.root
            .appendingPathComponent("conversations")
            .appendingPathComponent("[11111111-2222-3333-4444-555555555555].md")

        #expect(sandbox.store.fileURL(for: entryID).path == expected.path)
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    @Test func fileIsReadableMarkdown() throws {
        let sandbox = Sandbox()
        sandbox.store.save(sample(), entryID: entryID)

        let content = try String(contentsOf: sandbox.store.fileURL(for: entryID), encoding: .utf8)

        #expect(content.hasPrefix("# Talk\n"))
        #expect(content.contains("## Dear Diary · "))
        #expect(content.contains("## You · "))
        #expect(content.contains("That she'd think I can't handle it."))
    }

    @Test func keepsLineBreaksAndUnusualText() {
        let sandbox = Sandbox()
        let tricky = [
            TalkMessage(speaker: .you, text: "First line\n\nThird line with \"quotes\" and emoji 🙂", date: start),
            TalkMessage(speaker: .diary, text: "## You · 2026-11-10 21:42:07\nThat line only looks like a heading.", date: start.addingTimeInterval(5)),
            TalkMessage(speaker: .you, text: "\\## already has a backslash\n\\\\## and this one has two\n## just a markdown heading", date: start.addingTimeInterval(9)),
        ]

        sandbox.store.save(tricky, entryID: entryID)

        #expect(sandbox.store.load(entryID: entryID) == tricky)
    }

    @Test func nothingSavedMeansAnEmptyConversation() {
        let sandbox = Sandbox()

        #expect(sandbox.store.load(entryID: entryID).isEmpty)
    }

    @Test func savingAnEmptyConversationRemovesTheFile() {
        let sandbox = Sandbox()
        sandbox.store.save(sample(), entryID: entryID)

        #expect(sandbox.store.save([], entryID: entryID))

        #expect(!FileManager.default.fileExists(atPath: sandbox.store.fileURL(for: entryID).path))
    }

    @Test func deleteRemovesOnlyThatEntrysConversation() {
        let sandbox = Sandbox()
        let otherID = UUID()
        sandbox.store.save(sample(), entryID: entryID)
        sandbox.store.save(sample(), entryID: otherID)

        #expect(sandbox.store.delete(entryID: entryID))

        #expect(sandbox.store.load(entryID: entryID).isEmpty)
        #expect(sandbox.store.load(entryID: otherID) == sample())
        #expect(sandbox.store.delete(entryID: entryID))
    }

    @Test func aHandEditedFileIsStillUnderstood() {
        let edited = """
        some note I typed at the top by hand

        ## You · 2026-11-10 21:42:07

        Hello.



        ## Dear Diary · 2026-11-10 21:42:15
        Hi.
        ## Someone Else · 2026-11-10 21:42:20
        (not one of ours, so it stays part of the reply above)
        """

        let messages = ConversationStore.parse(edited)

        #expect(messages.count == 2)
        #expect(messages[0].speaker == .you)
        #expect(messages[0].text == "Hello.")
        #expect(messages[1].speaker == .diary)
        #expect(messages[1].text.hasPrefix("Hi.\n## Someone Else"))
    }
}
