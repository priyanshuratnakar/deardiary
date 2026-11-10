//
//  VersionsTests.swift
//  freewriteTests
//
//  Checks versions: how copies are stored, when the keeper saves one, and how
//  the versions screen lists and restores them. Everything happens in a
//  throwaway folder with made-up entries and a clock the test controls.
//

import Foundation
import Testing
@testable import freewrite

/// A keeper over a throwaway journal folder.
private func makeKeeper(
    _ sandbox: MemorySandbox,
    limits: VersionLimits = VersionLimits(),
    enabled: @escaping () -> Bool = { true }
) -> SnapshotKeeper {
    SnapshotKeeper(environment: VersionEnvironment(
        isEnabled: enabled,
        store: SnapshotStore(root: sandbox.root),
        journal: sandbox.journal,
        now: { sandbox.clock },
        limits: limits
    ))
}

private func offered(_ keeper: SnapshotKeeper) async -> Set<UUID> {
    await MainActor.run { keeper.index.entries }
}

private func minutes(_ count: Double) -> TimeInterval { count * 60 }

@Suite struct SnapshotStoreTests {

    @Test func aCopyIsAPlainFileNamedByItsTime() throws {
        let sandbox = MemorySandbox()
        let store = SnapshotStore(root: sandbox.root)
        let id = MemoryWeek.monday.id

        let version = try store.save("A line.\nAnother.", for: id, at: MemoryWeek.day(9, hour: 21, minute: 5))

        #expect(version.url.path.hasSuffix("/versions/[\(id.uuidString)]/[2026-11-09-21-05-00].md"))
        #expect(try String(contentsOf: version.url, encoding: .utf8) == "A line.\nAnother.")
        #expect(store.text(of: version) == "A line.\nAnother.")
        #expect(version.savedAt == MemoryWeek.day(9, hour: 21, minute: 5))
    }

    @Test func copiesAreListedNewestFirstAndOtherFilesAreIgnored() throws {
        let sandbox = MemorySandbox()
        let store = SnapshotStore(root: sandbox.root)
        let id = MemoryWeek.monday.id
        try store.save("one", for: id, at: MemoryWeek.day(9, hour: 9))
        try store.save("three", for: id, at: MemoryWeek.day(9, hour: 21))
        try store.save("two", for: id, at: MemoryWeek.day(9, hour: 15))
        try "not a version".write(to: store.folder(for: id).appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let versions = store.versions(of: id)

        #expect(versions.compactMap(store.text(of:)) == ["three", "two", "one"])
        #expect(store.versions(of: UUID()).isEmpty)
    }

    @Test func twoCopiesInTheSameSecondBothSurvive() throws {
        let sandbox = MemorySandbox()
        let store = SnapshotStore(root: sandbox.root)
        let id = MemoryWeek.monday.id
        let moment = MemoryWeek.day(9, hour: 21)

        let first = try store.save("first", for: id, at: moment)
        let second = try store.save("second", for: id, at: moment)

        #expect(first.url != second.url)
        #expect(store.versions(of: id).compactMap(store.text(of:)) == ["second", "first"])
    }

    @Test func itKnowsWhichEntriesHaveCopiesAndCanTrimAndDeleteThem() throws {
        let sandbox = MemorySandbox()
        let store = SnapshotStore(root: sandbox.root)
        let monday = MemoryWeek.monday.id
        let friday = MemoryWeek.friday.id
        for hour in 1...5 {
            try store.save("monday \(hour)", for: monday, at: MemoryWeek.day(9, hour: hour))
        }
        try store.save("friday", for: friday, at: MemoryWeek.day(9, hour: 3))

        let known = store.newestByEntry()
        #expect(known[monday]?.count == 5)
        #expect(known[monday].flatMap { store.text(of: $0.newest) } == "monday 5")
        #expect(known[friday]?.count == 1)

        store.trim(monday, keeping: 2)
        #expect(store.versions(of: monday).compactMap(store.text(of:)) == ["monday 5", "monday 4"])

        store.deleteAll(for: monday)
        #expect(store.versions(of: monday).isEmpty)
        #expect(store.newestByEntry().keys.sorted { $0.uuidString < $1.uuidString } == [friday])
    }
}

@Suite struct SnapshotKeeperTests {

    @Test func withVersionsOffNothingIsSaved() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let keeper = makeKeeper(sandbox, enabled: { false })

        #expect(await keeper.runPass() == 0)

        #expect(FileManager.default.fileExists(atPath: SnapshotStore(root: sandbox.root).folder.path) == false)
        #expect(await offered(keeper).isEmpty)
    }

    @Test func anEntryThatIsAlreadyThereGetsOneCopyAndIsNotOfferedUntilItChanges() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let store = SnapshotStore(root: sandbox.root)
        let keeper = makeKeeper(sandbox)

        #expect(await keeper.runPass() == 1)
        #expect(store.versions(of: MemoryWeek.monday.id).compactMap(store.text(of:)) == [MemoryWeek.monday.text])
        // The only copy is the same as the entry, so there is nothing earlier to open.
        #expect(await offered(keeper).isEmpty)

        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(30))
        #expect(await keeper.runPass() == 0)
        #expect(store.versions(of: MemoryWeek.monday.id).count == 1)
    }

    @Test func anEditIsOfferedStraightAwayAndCopiedOnceFiveMinutesHavePassed() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let store = SnapshotStore(root: sandbox.root)
        let keeper = makeKeeper(sandbox)
        await keeper.runPass()

        // Two minutes later the entry is edited.
        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(2))
        sandbox.writeEntry(MemoryWeek.monday, text: MemoryWeek.monday.text + "\nOne more line.", quietFor: 0)
        #expect(await keeper.runPass() == 0)
        #expect(await offered(keeper) == [MemoryWeek.monday.id])
        #expect(store.versions(of: MemoryWeek.monday.id).count == 1)

        // Five minutes after the first copy, the changed text is copied too.
        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(4))
        #expect(await keeper.runPass() == 1)
        #expect(store.versions(of: MemoryWeek.monday.id).compactMap(store.text(of:)) == [
            MemoryWeek.monday.text + "\nOne more line.",
            MemoryWeek.monday.text,
        ])
        #expect(await offered(keeper) == [MemoryWeek.monday.id])
    }

    @Test func aNewEntryWaitsFiveMinutesForItsFirstCopy() async {
        let sandbox = MemorySandbox()
        let entry = MemoryWeek.Entry(id: UUID(), startedAt: sandbox.clock.addingTimeInterval(-60), text: "A first line.")
        sandbox.writeEntry(entry, quietFor: 10)
        let store = SnapshotStore(root: sandbox.root)
        let keeper = makeKeeper(sandbox)

        #expect(await keeper.runPass() == 0)

        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(5))
        #expect(await keeper.runPass() == 1)
        #expect(store.versions(of: entry.id).count == 1)
    }

    @Test func whileAnEntryKeepsChangingACopyIsKeptEveryFiveMinutesNotEveryMinute() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let store = SnapshotStore(root: sandbox.root)
        let keeper = makeKeeper(sandbox)
        await keeper.runPass()

        // Twelve minutes of writing, with the keeper looking once a minute.
        var saved = 0
        for minute in 1...12 {
            sandbox.clock = sandbox.clock.addingTimeInterval(60)
            sandbox.writeEntry(MemoryWeek.monday, text: MemoryWeek.monday.text + "\nLine \(minute).", quietFor: 0)
            saved += await keeper.runPass()
        }

        #expect(saved == 2)
        #expect(store.versions(of: MemoryWeek.monday.id).compactMap(store.text(of:)) == [
            MemoryWeek.monday.text + "\nLine 10.",
            MemoryWeek.monday.text + "\nLine 5.",
            MemoryWeek.monday.text,
        ])
    }

    @Test func textThatHasNotChangedIsNeverCopiedTwice() async {
        let sandbox = MemorySandbox()
        let url = sandbox.writeEntry(MemoryWeek.monday)
        let store = SnapshotStore(root: sandbox.root)
        let keeper = makeKeeper(sandbox)
        await keeper.runPass()

        // The file is saved again with the same words (for example typing a letter and removing it).
        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(10))
        sandbox.touch(url, quietFor: 0)

        #expect(await keeper.runPass() == 0)
        #expect(await keeper.runPass() == 0)
        #expect(store.versions(of: MemoryWeek.monday.id).count == 1)
    }

    @Test func emptyEntriesVideoEntriesAndTheWelcomeGuideAreSkipped() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.Entry(id: UUID(), startedAt: MemoryWeek.day(3), text: "\n\n"))
        sandbox.writeEntry(MemoryWeek.Entry(id: UUID(), startedAt: MemoryWeek.day(4), text: "Video Entry"))
        sandbox.writeEntry(MemoryWeek.Entry(id: UUID(), startedAt: MemoryWeek.day(5), text: MemorySandbox.welcomeText))
        let keeper = makeKeeper(sandbox)

        #expect(await keeper.runPass() == 0)
        #expect(SnapshotStore(root: sandbox.root).newestByEntry().isEmpty)
    }

    @Test func onlyTheNewestCopiesAreKept() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday, text: "Draft 0.")
        let store = SnapshotStore(root: sandbox.root)
        var limits = VersionLimits()
        limits.keep = 3
        let keeper = makeKeeper(sandbox, limits: limits)
        await keeper.runPass()

        for draft in 1...5 {
            sandbox.clock = sandbox.clock.addingTimeInterval(minutes(6))
            sandbox.writeEntry(MemoryWeek.monday, text: "Draft \(draft).", quietFor: 0)
            await keeper.runPass()
        }

        #expect(store.versions(of: MemoryWeek.monday.id).compactMap(store.text(of:)) == ["Draft 5.", "Draft 4.", "Draft 3."])
    }

    @Test func theEntriesThemselvesAreNeverChanged() async throws {
        let sandbox = MemorySandbox()
        let urls = MemoryWeek.entries.map { sandbox.writeEntry($0) }
        func state() throws -> [String] {
            try urls.map { url in
                let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return "\(try String(contentsOf: url, encoding: .utf8))|\(modified?.timeIntervalSince1970 ?? 0)"
            }
        }
        let before = try state()
        let keeper = makeKeeper(sandbox)

        #expect(await keeper.runPass() == 4)
        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(20))
        await keeper.runPass()

        #expect(try state() == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.root.path).filter { $0.hasSuffix(".md") }.count == 4)
    }

    @Test func theEntryAsItReadsNowIsKeptBeforeARestoreWhateverTheTime() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let store = SnapshotStore(root: sandbox.root)
        let keeper = makeKeeper(sandbox)
        await keeper.runPass()

        // One minute later, well inside the five minutes.
        sandbox.clock = sandbox.clock.addingTimeInterval(60)
        #expect(await keeper.keep("What is on the page now.", for: MemoryWeek.monday.id))
        #expect(store.versions(of: MemoryWeek.monday.id).compactMap(store.text(of:)) == ["What is on the page now.", MemoryWeek.monday.text])

        // Keeping the same text again adds nothing, and an empty page has nothing to keep.
        #expect(await keeper.keep("What is on the page now.", for: MemoryWeek.monday.id))
        #expect(await keeper.keep("  \n\n", for: MemoryWeek.monday.id))
        #expect(store.versions(of: MemoryWeek.monday.id).count == 2)
    }

    @Test func deletingAnEntryRemovesItsCopies() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        sandbox.writeEntry(MemoryWeek.friday)
        let store = SnapshotStore(root: sandbox.root)
        let keeper = makeKeeper(sandbox)
        await keeper.runPass()
        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(6))
        sandbox.writeEntry(MemoryWeek.monday, text: "Changed.", quietFor: 0)
        sandbox.writeEntry(MemoryWeek.friday, text: "Changed too.", quietFor: 0)
        await keeper.runPass()
        #expect(await offered(keeper) == [MemoryWeek.monday.id, MemoryWeek.friday.id])

        sandbox.deleteEntry(MemoryWeek.monday)
        await keeper.forget(MemoryWeek.monday.id)

        #expect(store.versions(of: MemoryWeek.monday.id).isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.folder(for: MemoryWeek.monday.id).path) == false)
        #expect(store.versions(of: MemoryWeek.friday.id).count == 2)
        #expect(await offered(keeper) == [MemoryWeek.friday.id])
    }

    @Test func switchingVersionsOffHidesThemAndLeavesTheFilesAlone() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let store = SnapshotStore(root: sandbox.root)
        var isOn = true
        let keeper = makeKeeper(sandbox, enabled: { isOn })
        await keeper.runPass()
        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(6))
        sandbox.writeEntry(MemoryWeek.monday, text: "Changed.", quietFor: 0)
        await keeper.runPass()
        #expect(await offered(keeper) == [MemoryWeek.monday.id])

        isOn = false
        sandbox.clock = sandbox.clock.addingTimeInterval(minutes(6))
        sandbox.writeEntry(MemoryWeek.monday, text: "Changed again.", quietFor: 0)
        #expect(await keeper.runPass() == 0)

        #expect(await offered(keeper).isEmpty)
        #expect(store.versions(of: MemoryWeek.monday.id).count == 2)

        // Switched back on, it carries on from where it was.
        isOn = true
        #expect(await keeper.runPass() == 1)
        #expect(await offered(keeper) == [MemoryWeek.monday.id])
    }

    @Test func ifTheFolderCannotBeWrittenItSaysSoInOneLineAndCarriesOnLater() async throws {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let store = SnapshotStore(root: sandbox.root)
        // Something that is not a folder sits where the versions folder should be.
        try "in the way".write(to: store.folder, atomically: true, encoding: .utf8)
        let keeper = makeKeeper(sandbox)

        #expect(await keeper.runPass() == 0)
        #expect(await MainActor.run { keeper.index.problem } == "Couldn't save versions to the journal folder.")

        try FileManager.default.removeItem(at: store.folder)
        #expect(await keeper.runPass() == 1)
        #expect(await MainActor.run { keeper.index.problem } == nil)
    }
}

@MainActor
@Suite struct VersionsModelTests {

    /// A journal folder with Monday's entry as it reads now, and earlier copies of it.
    private func sandbox(current: String, earlier: [(text: String, hour: Int)]) throws -> MemorySandbox {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday, text: current)
        let store = SnapshotStore(root: sandbox.root)
        for copy in earlier {
            try store.save(copy.text, for: MemoryWeek.monday.id, at: MemoryWeek.day(9, hour: copy.hour))
        }
        return sandbox
    }

    private func model(_ sandbox: MemorySandbox, keep: ((String, UUID) async -> Bool)? = nil) -> VersionsModel {
        let keeper = makeKeeper(sandbox)
        return VersionsModel(
            entryID: MemoryWeek.monday.id,
            store: SnapshotStore(root: sandbox.root),
            journal: sandbox.journal,
            keep: keep ?? { await keeper.keep($0, for: $1) }
        )
    }

    @Test func theListIsNewestFirstAndOpensOnTheNewestVersionThatDiffers() async throws {
        let sandbox = try sandbox(current: "One two three.", earlier: [("One.", 9), ("One two.", 12), ("One two three.", 15)])
        let model = model(sandbox)
        #expect(model.isLoading)

        await model.load()

        #expect(model.isLoading == false)
        #expect(model.rows.map(\.text) == ["One two three.", "One two.", "One."])
        #expect(model.rows.map(\.isCurrent) == [true, false, false])
        #expect(model.rows.map(\.words) == [3, 2, 1])
        #expect(model.selected?.text == "One two.")
        #expect(model.entryStartedAt == MemoryWeek.monday.startedAt)
    }

    @Test func blankLinesAtTheTopDoNotMakeAVersionLookDifferent() async throws {
        // freewrite used to start every entry with two blank lines and now drops them on opening.
        let sandbox = try sandbox(current: "The same words.", earlier: [("\n\nThe same words.", 9)])
        let model = model(sandbox)

        await model.load()

        #expect(model.rows.map(\.isCurrent) == [true])
        #expect(VersionText.forPage("\n\nThe same words.") == "The same words.")
    }

    @Test func restoringHandsBackTheVersionAndKeepsWhatWasThereFirst() async throws {
        let sandbox = try sandbox(current: "What is on the page now.", earlier: [("\n\nAn earlier draft.", 9)])
        let store = SnapshotStore(root: sandbox.root)
        let model = model(sandbox)
        await model.load()

        let restored = await model.restore()

        // The text for the page, without the old blank lines at the top.
        #expect(restored == "An earlier draft.")
        #expect(model.note == nil)
        // What was on the page is now the newest copy, so the restore can be undone.
        #expect(store.versions(of: MemoryWeek.monday.id).compactMap(store.text(of:)) == ["What is on the page now.", "\n\nAn earlier draft."])
    }

    @Test func aRestoreCanBeUndone() async throws {
        let sandbox = try sandbox(current: "What is on the page now.", earlier: [("An earlier draft.", 9)])
        let first = model(sandbox)
        await first.load()
        let restored = try #require(await first.restore())

        // The page saves the restored text, as freewrite does on every change.
        sandbox.writeEntry(MemoryWeek.monday, text: restored, quietFor: 0)

        let second = model(sandbox)
        await second.load()
        #expect(second.rows.map(\.text) == ["What is on the page now.", "An earlier draft."])
        #expect(second.rows.map(\.isCurrent) == [false, true])
        #expect(second.selected?.text == "What is on the page now.")
        #expect(await second.restore() == "What is on the page now.")
    }

    @Test func theVersionThatMatchesTheEntryCannotBeRestored() async throws {
        let sandbox = try sandbox(current: "One two.", earlier: [("One.", 9), ("One two.", 12)])
        let store = SnapshotStore(root: sandbox.root)
        let model = model(sandbox)
        await model.load()
        model.selectedID = model.rows.first?.id

        #expect(await model.restore() == nil)
        #expect(store.versions(of: MemoryWeek.monday.id).count == 2)
    }

    @Test func ifWhatIsThereCannotBeKeptNothingIsRestored() async throws {
        let sandbox = try sandbox(current: "What is on the page now.", earlier: [("An earlier draft.", 9)])
        let model = model(sandbox, keep: { _, _ in false })
        await model.load()

        #expect(await model.restore() == nil)
        #expect(model.note == "Couldn't keep the entry as it reads now, so nothing was restored.")
    }

    @Test func anEntryWithNoVersionsShowsNone() async throws {
        let sandbox = try sandbox(current: "Just this.", earlier: [])
        let model = model(sandbox)

        await model.load()

        #expect(model.rows.isEmpty)
        #expect(model.selected == nil)
        #expect(model.isLoading == false)
        #expect(await model.restore() == nil)
    }

    @Test func wordsAreCountedPlainly() {
        #expect(VersionText.words("") == 0)
        #expect(VersionText.words("One") == 1)
        #expect(VersionText.words("  One\n\ntwo   three.  ") == 3)
        #expect(VersionText.wordsLine(1) == "1 word")
        #expect(VersionText.wordsLine(412) == "412 words")
    }
}

@Suite struct VersionSettingsTests {

    @Test func versionsAreOffUntilSwitchedOnAndTheChoiceIsRemembered() throws {
        let suiteName = "deardiary.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = VersionSettings(defaults: defaults)
        #expect(settings.enabled == false)
        #expect(settings.isOn() == false)

        settings.enabled = true
        #expect(settings.isOn())
        #expect(VersionSettings(defaults: defaults).enabled)
    }

    @Test func underTestTheAppsOwnSwitchIsAThrowawayCopyAndOff() {
        #expect(VersionSettings.shared.isOn() == false)
    }
}
