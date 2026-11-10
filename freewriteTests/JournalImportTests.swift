//
//  JournalImportTests.swift
//  freewriteTests
//
//  Checks the first run and moving in: the welcome page a new journal opens
//  on, what is found in a freewrite folder and what is left behind, that
//  copying never changes the originals or anything already here, what Settings
//  says at each step, and that memory leaves copied entries alone until a
//  rebuild. Both folders are throwaway and every entry is made up.
//

import Combine
import Foundation
import Testing
@testable import freewrite

/// A pretend freewrite folder next to a pretend Dear Diary journal.
private final class MovingIn: @unchecked Sendable {
    /// Where "freewrite" keeps its entries.
    let old: URL
    /// Dear Diary's journal.
    let home = MemorySandbox()
    let record: ImportRecord
    private let suite = "deardiary.tests.import.\(UUID().uuidString)"

    enum VideoLayout {
        /// Videos/[entry]/[entry].mov with a thumbnail and a transcript: how freewrite stores it now.
        case folder
        /// Videos/[entry].mov: an older layout.
        case loose
        /// [entry].mov beside the entry: the oldest layout.
        case beside
    }

    init() {
        old = FileManager.default.temporaryDirectory
            .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Freewrite", isDirectory: true)
        try? FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        record = ImportRecord(defaults: UserDefaults(suiteName: suite)!)
        home.broughtInAt = { [record] in record.date(for: $0) }
    }

    static func name(_ entry: MemoryWeek.Entry) -> String {
        MemorySandbox.filename(id: entry.id, startedAt: entry.startedAt)
    }

    /// Writes an entry into the pretend freewrite folder.
    @discardableResult
    func writeOld(_ entry: MemoryWeek.Entry, text: String? = nil, editedAt: Date? = nil, in folder: URL? = nil) -> URL {
        let url = (folder ?? old).appendingPathComponent(Self.name(entry))
        try? (text ?? entry.text).write(to: url, atomically: true, encoding: .utf8)
        if let editedAt {
            try? FileManager.default.setAttributes([.modificationDate: editedAt], ofItemAtPath: url.path)
        }
        return url
    }

    /// A made-up entry on a day of its own.
    static func entry(_ number: Int, text: String = "A made-up line.") -> MemoryWeek.Entry {
        MemoryWeek.Entry(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000001\(String(format: "%02d", number))")!,
            startedAt: MemoryWeek.day(1, hour: 6, minute: number),
            text: text
        )
    }

    /// Gives an entry in the pretend freewrite folder a made-up video.
    func addVideo(to entry: MemoryWeek.Entry, layout: VideoLayout, bytes: Int = 4_000) {
        let base = String(Self.name(entry).dropLast(3))
        let manager = FileManager.default
        let film = Data(count: bytes)
        switch layout {
        case .folder:
            let folder = old.appendingPathComponent("Videos/\(base)", isDirectory: true)
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? film.write(to: folder.appendingPathComponent("\(base).mov"))
            try? Data(count: 500).write(to: folder.appendingPathComponent("thumbnail.jpg"))
            try? "Made-up words said to the camera.".write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        case .loose:
            let folder = old.appendingPathComponent("Videos", isDirectory: true)
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? film.write(to: folder.appendingPathComponent("\(base).mov"))
        case .beside:
            try? film.write(to: old.appendingPathComponent("\(base).mov"))
        }
    }

    func plan(from folder: URL? = nil) -> ImportPlan {
        JournalImporter.scan(folder ?? old, into: home.root, reader: home.journal)
    }

    /// The section in Settings, with a folder picker that answers at once.
    @MainActor
    func section(picking folder: URL?) -> JournalImport {
        JournalImport(root: home.root, reader: home.journal, record: record, now: { [home] in home.clock }, pickFolder: { folder })
    }

    func isHere(_ entry: MemoryWeek.Entry) -> Bool {
        FileManager.default.fileExists(atPath: home.root.appendingPathComponent(Self.name(entry)).path)
    }

    func textHere(_ entry: MemoryWeek.Entry) -> String? {
        try? String(contentsOf: home.root.appendingPathComponent(Self.name(entry)), encoding: .utf8)
    }

    func exists(_ path: String, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path)
    }
}

// MARK: - The welcome page

@Suite struct WelcomeTests {

    @Test func aNewJournalOpensOnDearDiarysOwnWelcome() throws {
        let welcome = try #require(JournalReader.bundledWelcomeText())

        #expect(welcome.hasPrefix("Dear Diary"))
        #expect(welcome.contains("Nothing you write leaves this Mac unless you ask it to."))
        #expect(welcome.contains("click New Entry"))
        #expect(!welcome.contains("Welcome to Freewrite"))
    }

    @Test func freewritesGuideIsStillBundledAndStillCountsAsAWelcome() throws {
        let guide = try #require(JournalReader.bundledEarlierWelcomeTexts().first)
        let welcome = try #require(JournalReader.bundledWelcomeText())
        let reader = JournalReader(root: FileManager.default.temporaryDirectory)

        #expect(guide.contains("Welcome to Freewrite"))
        #expect(reader.isWelcome(guide))
        #expect(reader.isWelcome(welcome))
        // The page adds blank lines at the top; that does not make it the user's writing.
        #expect(reader.isWelcome("\n\n" + guide + "\n"))
        #expect(!reader.isWelcome("My own words about the day."))
        #expect(!reader.isWelcome(""))
        #expect(!reader.isWelcome("\n\n"))
    }

    @Test func aJournalThatStillHoldsFreewritesGuideNeverSendsItOrCopiesIt() async throws {
        let guide = try #require(JournalReader.bundledEarlierWelcomeTexts().first)
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday, text: "\n\n" + guide)
        let provider = FakeProvider()
        let engine = sandbox.engine(provider)

        let file = try #require(sandbox.journal.entryFiles()?.first)
        #expect(!sandbox.journal.isDigestible(guide, file: file))
        #expect(await engine.runPass() == .finished(digested: 0))
        #expect(provider.requests.isEmpty)
        #expect(await engine.entriesToRebuild() == 0)
    }
}

// MARK: - Looking through a folder, and copying

@Suite struct JournalImporterTests {

    @Test func entriesAreFoundOldestFirstAndTheRestIsLeftBehind() throws {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.friday)
        moving.writeOld(MemoryWeek.monday)
        moving.writeOld(MemoryWeek.wednesday)
        // Left behind: empty pages, welcome guides, and files that are not entries.
        moving.writeOld(MovingIn.entry(1), text: "")
        moving.writeOld(MovingIn.entry(2), text: "\n\n  \n")
        moving.writeOld(MovingIn.entry(3), text: MemorySandbox.welcomeText)
        moving.writeOld(MovingIn.entry(4), text: "\n\n" + (try #require(JournalReader.bundledEarlierWelcomeTexts().first)))
        try "A shopping list.".write(to: moving.old.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "Not named like an entry.".write(to: moving.old.appendingPathComponent("ideas.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: moving.old.appendingPathComponent("Exports"), withIntermediateDirectories: true)

        let plan = moving.plan()

        #expect(plan.items.map(\.filename) == [MemoryWeek.monday, MemoryWeek.wednesday, MemoryWeek.friday].map(MovingIn.name))
        #expect(plan.alreadyHere == 0)
        #expect(plan.found == 3)
        #expect(plan.videos == 0)
        #expect(plan.source.standardizedFileURL == moving.old.standardizedFileURL)
        let sizeOfTheText = [MemoryWeek.monday, MemoryWeek.wednesday, MemoryWeek.friday].map { Int64($0.text.utf8.count) }.reduce(0, +)
        #expect(plan.bytes == sizeOfTheText)
    }

    @Test func entriesThatAreAlreadyHereAreCountedAndNotCopiedAgain() {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        moving.writeOld(MemoryWeek.wednesday)
        moving.home.writeEntry(MemoryWeek.monday, text: "Edited here since it was copied.")

        let plan = moving.plan()

        #expect(plan.items.map(\.filename) == [MovingIn.name(MemoryWeek.wednesday)])
        #expect(plan.alreadyHere == 1)
        #expect(plan.found == 2)
    }

    @Test func aFolderThatHoldsTheFreewriteFolderWorksToo() {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        let documents = moving.old.deletingLastPathComponent()

        let plan = moving.plan(from: documents)

        #expect(plan.items.count == 1)
        #expect(plan.source.standardizedFileURL == moving.old.standardizedFileURL)
    }

    @Test func aFolderWithNothingInItFindsNothing() {
        let moving = MovingIn()

        let plan = moving.plan()

        #expect(plan.items.isEmpty)
        #expect(plan.found == 0)
        #expect(plan.bytes == 0)
    }

    @Test func videosComeWithTheirEntriesWhereverFreewriteKeptThem() throws {
        let moving = MovingIn()
        let now = MovingIn.entry(11, text: "Video Entry")
        let older = MovingIn.entry(12, text: "Video Entry")
        let oldest = MovingIn.entry(13, text: "Video Entry")
        let lost = MovingIn.entry(14, text: "Video Entry")
        for entry in [now, older, oldest, lost] {
            moving.writeOld(entry)
        }
        moving.addVideo(to: now, layout: .folder, bytes: 4_000)
        moving.addVideo(to: older, layout: .loose, bytes: 3_000)
        moving.addVideo(to: oldest, layout: .beside, bytes: 2_000)
        func base(_ entry: MemoryWeek.Entry) -> String { String(MovingIn.name(entry).dropLast(3)) }

        let plan = moving.plan()

        // A video entry whose video is gone is two words and nothing else, so it stays behind.
        #expect(plan.items.map(\.filename) == [now, older, oldest].map(MovingIn.name))
        #expect(plan.videos == 3)
        #expect(plan.items[0].videoPaths == ["Videos/\(base(now))"])
        #expect(plan.items[1].videoPaths == ["Videos/\(base(older)).mov"])
        #expect(plan.items[2].videoPaths == ["\(base(oldest)).mov"])
        #expect(plan.bytes >= 9_500)

        for item in plan.items {
            try JournalImporter.copy(item, from: plan.source, into: moving.home.root)
        }

        let here = moving.home.root
        #expect(moving.exists("Videos/\(base(now))/\(base(now)).mov", in: here))
        #expect(moving.exists("Videos/\(base(now))/thumbnail.jpg", in: here))
        #expect(moving.exists("Videos/\(base(now))/transcript.md", in: here))
        #expect(moving.exists("Videos/\(base(older)).mov", in: here))
        #expect(moving.exists("\(base(oldest)).mov", in: here))
        #expect(moving.textHere(now) == "Video Entry")
        // The originals are where they were.
        #expect(moving.exists("Videos/\(base(now))/\(base(now)).mov", in: moving.old))
        #expect(moving.exists("Videos/\(base(older)).mov", in: moving.old))
        #expect(moving.exists("\(base(oldest)).mov", in: moving.old))
        // And memory and versions treat them as video entries, as they do for videos recorded here.
        let files = try #require(moving.home.journal.entryFiles())
        #expect(files.count == 3)
        #expect(files.allSatisfy { !moving.home.journal.isDigestible("Video Entry", file: $0) })
    }

    @Test func copyingLeavesTheOriginalAndNeverReplacesWhatIsHere() throws {
        let moving = MovingIn()
        let original = moving.writeOld(MemoryWeek.monday)
        moving.writeOld(MemoryWeek.wednesday)
        let plan = moving.plan()
        // Something with Wednesday's name turns up here between looking and copying.
        moving.home.writeEntry(MemoryWeek.wednesday, text: "Written here.")

        for item in plan.items {
            try JournalImporter.copy(item, from: plan.source, into: moving.home.root)
        }

        #expect(moving.textHere(MemoryWeek.monday) == MemoryWeek.monday.text)
        #expect(try String(contentsOf: original, encoding: .utf8) == MemoryWeek.monday.text)
        #expect(moving.textHere(MemoryWeek.wednesday) == "Written here.")
    }

    @Test func aCopyKeepsTheDayTheEntryWasLastEdited() throws {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday, editedAt: MemoryWeek.day(3, hour: 9))

        for item in moving.plan().items {
            try JournalImporter.copy(item, from: moving.old, into: moving.home.root)
        }

        let file = try #require(moving.home.journal.entryFiles()?.first)
        #expect(abs(file.modifiedAt.timeIntervalSince(MemoryWeek.day(3, hour: 9))) < 1)
        #expect(file.startedAt == MemoryWeek.monday.startedAt)
    }
}

// MARK: - The section in Settings

@Suite @MainActor struct JournalImportTests {

    @Test func pickingAFolderSaysWhatWasFoundAndCopiesNothingYet() async throws {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        moving.writeOld(MemoryWeek.wednesday)
        moving.writeOld(MemoryWeek.friday)
        let video = MovingIn.entry(11, text: "Video Entry")
        moving.writeOld(video)
        moving.addVideo(to: video, layout: .folder, bytes: 300_000)
        moving.home.writeEntry(MemoryWeek.monday)
        let section = moving.section(picking: moving.old)
        #expect(section.line == nil)
        #expect(section.canChoose)

        await section.choose()

        guard case .found(let plan) = section.state else {
            Issue.record("Expected to be told what was found.")
            return
        }
        #expect(plan.items.count == 3)
        let line = try #require(section.line)
        #expect(line.hasPrefix("Found 4 entries and 1 video ("))
        #expect(line.hasSuffix("). 1 is already here."))
        #expect(section.copyWord == "Copy 3 entries")
        #expect(!section.canChoose)
        #expect(!moving.isHere(MemoryWeek.wednesday))
    }

    @Test func cancelBacksOutWithNothingCopied() async {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        let section = moving.section(picking: moving.old)
        await section.choose()
        #expect(section.copyWord == "Copy 1 entry")

        section.cancel()

        #expect(section.state == .idle)
        #expect(section.line == nil)
        #expect(!moving.isHere(MemoryWeek.monday))
    }

    @Test func closingTheFolderPickerChangesNothing() async {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        let section = moving.section(picking: nil)

        await section.choose()

        #expect(section.state == .idle)
    }

    @Test func aFolderWithNoEntriesSaysSoAndAnotherCanBePicked() async throws {
        let moving = MovingIn()
        try "A shopping list.".write(to: moving.old.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let section = moving.section(picking: moving.old)

        await section.choose()

        #expect(section.state == .nothing)
        #expect(section.line == "No freewrite entries in that folder. The folder is usually called Freewrite.")
        #expect(section.canChoose)
    }

    @Test func whenEverythingIsHereAlreadyItSaysSo() async {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        moving.home.writeEntry(MemoryWeek.monday)
        let section = moving.section(picking: moving.old)

        await section.choose()
        #expect(section.state == .allHere(1))
        #expect(section.line == "Found 1 entry. It is already here.")

        moving.writeOld(MemoryWeek.friday)
        moving.home.writeEntry(MemoryWeek.friday)
        await section.choose()
        #expect(section.line == "Found 2 entries. All of them are already here.")
        #expect(section.copyWord == nil)
    }

    @Test func copyingBringsTheEntriesInAndTellsThePageOnce() async {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        moving.writeOld(MemoryWeek.friday)
        let section = moving.section(picking: moving.old)
        var told = 0
        let listening = section.didCopy.sink { told += 1 }
        defer { listening.cancel() }
        await section.choose()

        section.copy()
        await section.waitUntilCopied()

        #expect(section.state == .done(copied: 2, total: 2, failed: 0))
        #expect(section.line == "Copied 2 entries. They are in History now.")
        #expect(moving.textHere(MemoryWeek.monday) == MemoryWeek.monday.text)
        #expect(moving.textHere(MemoryWeek.friday) == MemoryWeek.friday.text)
        #expect(told == 1)
        #expect(section.canChoose)
        // Each copied entry is noted, so memory knows it came from freewrite.
        #expect(moving.record.date(for: MemoryWeek.monday.id) == moving.home.clock)
        #expect(moving.record.date(for: MemoryWeek.sunday.id) == nil)

        // Picking the same folder again finds nothing new.
        await section.choose()
        #expect(section.line == "Found 2 entries. All of them are already here.")
    }

    @Test func oneEntryIsSpokenOfAsOne() async {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        let section = moving.section(picking: moving.old)
        await section.choose()

        section.copy()
        await section.waitUntilCopied()

        #expect(section.line == "Copied 1 entry. It is in History now.")
    }

    @Test func stoppingBeforeTheFirstEntryCopiesNothing() async {
        let moving = MovingIn()
        moving.writeOld(MemoryWeek.monday)
        moving.writeOld(MemoryWeek.friday)
        let section = moving.section(picking: moving.old)
        var told = 0
        let listening = section.didCopy.sink { told += 1 }
        defer { listening.cancel() }
        await section.choose()

        section.copy()
        section.stop()
        await section.waitUntilCopied()

        #expect(section.state == .idle)
        #expect(!moving.isHere(MemoryWeek.monday))
        #expect(!moving.isHere(MemoryWeek.friday))
        #expect(told == 0)
    }

    @Test func anEntryThatCannotBeCopiedIsCountedAndTheRestCarryOn() async throws {
        let moving = MovingIn()
        let gone = moving.writeOld(MemoryWeek.monday)
        moving.writeOld(MemoryWeek.friday)
        let section = moving.section(picking: moving.old)
        await section.choose()
        // Monday disappears from the freewrite folder between looking and copying.
        try FileManager.default.removeItem(at: gone)

        section.copy()
        await section.waitUntilCopied()

        #expect(section.state == .done(copied: 1, total: 2, failed: 1))
        #expect(section.line == "Copied 1 of 2 entries. It is in History now. 1 could not be copied.")
        #expect(moving.isHere(MemoryWeek.friday))
    }

    @Test func whenNothingCanBeCopiedItSaysSoAndThePageIsNotTold() async throws {
        let moving = MovingIn()
        let gone = moving.writeOld(MemoryWeek.monday)
        let section = moving.section(picking: moving.old)
        var told = 0
        let listening = section.didCopy.sink { told += 1 }
        defer { listening.cancel() }
        await section.choose()
        try FileManager.default.removeItem(at: gone)

        section.copy()
        await section.waitUntilCopied()

        #expect(section.state == .done(copied: 0, total: 1, failed: 1))
        #expect(section.line == "Couldn't copy the entries. Nothing was changed.")
        #expect(told == 0)
    }

    @Test func whileCopyingItSaysHowFarItIs() {
        let section = MovingIn().section(picking: nil)

        section.show(.copying(done: 0, total: 40))
        #expect(section.line == "Copying 1 of 40…")
        section.show(.copying(done: 11, total: 40))
        #expect(section.line == "Copying 12 of 40…")
        section.show(.copying(done: 40, total: 40))
        #expect(section.line == "Copying 40 of 40…")
        #expect(!section.canChoose)
    }

    @Test func theRecordOfCopiedEntriesSurvivesARestart() {
        let suite = "deardiary.tests.import.\(UUID().uuidString)"
        let id = MemoryWeek.monday.id
        ImportRecord(defaults: UserDefaults(suiteName: suite)!).note([id], at: MemoryWeek.day(9, hour: 21))

        let later = ImportRecord(defaults: UserDefaults(suiteName: suite)!)

        #expect(later.date(for: id) == MemoryWeek.day(9, hour: 21))
        #expect(later.date(for: MemoryWeek.friday.id) == nil)
    }
}

// MARK: - Copied entries and memory

@Suite @MainActor struct CopiedEntriesAndMemoryTests {

    /// Copies everything in the pretend freewrite folder into the journal.
    private func bringAcross(_ moving: MovingIn) async {
        let section = moving.section(picking: moving.old)
        await section.choose()
        section.copy()
        await section.waitUntilCopied()
    }

    @Test func copiedEntriesWaitForARebuildEvenIfEditedAfterMemoryWasSwitchedOn() async {
        let moving = MovingIn()
        moving.home.enabledSince = MemoryWeek.day(5)
        // Monday was last edited before memory was switched on; Friday after it, in freewrite.
        moving.writeOld(MemoryWeek.monday, editedAt: MemoryWeek.day(3))
        moving.writeOld(MemoryWeek.friday, editedAt: MemoryWeek.day(7))
        await bringAcross(moving)
        let provider = FakeProvider([.reply([DigestJSON.reply()]), .reply([DigestJSON.reply()])])
        let engine = moving.home.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 0))
        #expect(await engine.runPass(includeFresh: true) == .finished(digested: 0))
        #expect(provider.requests.isEmpty)
        #expect(await MainActor.run { engine.status.summary.waitingEntries } == 0)

        // A rebuild is the way to bring them in, and it says how many first.
        #expect(await engine.entriesToRebuild() == 2)
        await engine.rebuild()
        #expect(provider.requests.count == 2)
    }

    @Test func aCopiedEntryThatIsEditedHereIsReadLikeAnyOther() async {
        let moving = MovingIn()
        moving.home.enabledSince = MemoryWeek.day(5)
        moving.writeOld(MemoryWeek.monday, editedAt: MemoryWeek.day(3))
        moving.writeOld(MemoryWeek.friday, editedAt: MemoryWeek.day(7))
        await bringAcross(moving)
        let provider = FakeProvider([.reply([DigestJSON.reply()])])
        let engine = moving.home.engine(provider)

        // Two hours later, a line is added to Friday in Dear Diary.
        moving.home.clock = moving.home.clock.addingTimeInterval(2 * 3600)
        moving.home.writeEntry(MemoryWeek.friday, text: MemoryWeek.friday.text + "\n\nA line added here.", quietFor: 3600)

        #expect(await engine.runPass() == .finished(digested: 1))
        #expect(provider.requests.count == 1)
        #expect(provider.requests.first?.messages.first?.text.contains("A line added here.") == true)
    }

    @Test func entriesWrittenHereAreNotHeldBackByACopy() async {
        let moving = MovingIn()
        moving.home.enabledSince = MemoryWeek.day(5)
        moving.home.writeEntry(MemoryWeek.sunday, quietFor: moving.home.clock.timeIntervalSince(MemoryWeek.day(8, hour: 10)))
        moving.writeOld(MemoryWeek.monday, editedAt: MemoryWeek.day(7))
        await bringAcross(moving)
        let provider = FakeProvider([.reply([DigestJSON.reply()])])
        let engine = moving.home.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 1))
        #expect(provider.requests.count == 1)
        #expect(provider.requests.first?.messages.first?.text.contains("Too much coffee") == true)
    }
}
