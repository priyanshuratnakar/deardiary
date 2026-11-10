//
//  MemorySampleTests.swift
//  freewriteTests
//
//  Builds a whole memory folder from the made-up week of entries, using the
//  real engine with a pretend AI, and attaches the files it wrote to the test
//  results. This is the easiest way to see what the memory folder looks like
//  without a real journal or a real API call.
//

import XCTest
@testable import freewrite

final class MemorySampleTests: XCTestCase {

    func testAMadeUpWeekBecomesAReadableMemoryFolder() async throws {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        let provider = FakeProvider(MemoryWeek.replies.map { .reply([$0]) })

        let outcome = await sandbox.engine(provider).runPass()
        XCTAssertEqual(outcome, .finished(digested: 4))

        // Attach every file in the memory folder, named by its path inside it.
        let folder = sandbox.store.folder
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var paths: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "md" || url.pathExtension == "json" {
            let relative = url.path.replacingOccurrences(of: folder.path + "/", with: "")
            paths.append(relative)
            let attachment = XCTAttachment(string: try String(contentsOf: url, encoding: .utf8))
            attachment.name = "memory/" + relative
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        XCTAssertEqual(paths.sorted(), [
            "entries/00000000-0000-0000-0000-000000000001.json",
            "entries/00000000-0000-0000-0000-000000000002.json",
            "entries/00000000-0000-0000-0000-000000000003.json",
            "entries/00000000-0000-0000-0000-000000000004.json",
            "profile.md",
            "thoughts/arjun.md",
            "thoughts/meera.md",
            "thoughts/running.md",
            "thoughts/saying-yes-under-pressure.md",
            "thoughts/the-launch.md",
            "thoughts/the-pricing-page.md",
            "thoughts/trouble-sleeping.md",
        ])
    }

    /// Attaches the full instructions talk would be sent for a new entry that
    /// mentions Meera, with the made-up week in memory. Useful for reading
    /// exactly what leaves the Mac with a talk message.
    func testWhatTalkIsSentFromMemoryForANewEntry() throws {
        let built = try MemoryWeek.built()
        let entry = TalkEntry(
            id: UUID(uuidString: "99999999-0000-0000-0000-000000000000")!,
            text: "Meera wants an answer today and I still don't have one.",
            date: MemoryWeek.day(10)
        )
        let context = ContextBuilder.build(entry: entry, recentMessages: [], memory: built.memory, digests: built.digests)
        let system = Prompts.talkSystem(entryText: entry.text, entryDate: entry.date, memory: context)

        XCTAssertTrue(system.contains("<memory>"))
        XCTAssertTrue(system.contains("<entry>"))

        let attachment = XCTAttachment(string: system)
        attachment.name = "talk-instructions-with-memory"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
