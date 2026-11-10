//
//  StorageRootTests.swift
//  freewriteTests
//
//  Checks that the journal folder is the usual one in normal use, and a
//  throwaway one whenever tests are running or an override is set.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct StorageRootTests {

    private let documents = URL(fileURLWithPath: "/made-up/Documents", isDirectory: true)
    private let temporary = URL(fileURLWithPath: "/made-up/tmp", isDirectory: true)

    @Test func normalUseIsDocumentsFreewrite() {
        let root = StorageRoot.resolve(environment: [:], documentsDirectory: documents, temporaryDirectory: temporary)

        #expect(root.path == "/made-up/Documents/Freewrite")
    }

    @Test func overrideVariableWins() {
        let root = StorageRoot.resolve(
            environment: [
                StorageRoot.overrideVariable: "/made-up/dev-journal",
                "XCTestConfigurationFilePath": "/anything",
            ],
            documentsDirectory: documents,
            temporaryDirectory: temporary
        )

        #expect(root.path == "/made-up/dev-journal")
    }

    @Test func emptyOverrideIsIgnored() {
        let root = StorageRoot.resolve(
            environment: [StorageRoot.overrideVariable: ""],
            documentsDirectory: documents,
            temporaryDirectory: temporary
        )

        #expect(root.path == "/made-up/Documents/Freewrite")
    }

    @Test(arguments: ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"])
    func testRunsGetAThrowawayFolder(variable: String) {
        let root = StorageRoot.resolve(
            environment: [variable: "/anything"],
            documentsDirectory: documents,
            temporaryDirectory: temporary
        )

        #expect(root.path.hasPrefix("/made-up/tmp/DearDiary-Tests-"))
        #expect(root.lastPathComponent == "Freewrite")
        #expect(!root.path.contains("/Documents/"))
    }

    /// The tests start the real app. This proves that app is not looking at the journal.
    @Test func theAppUnderTestIsNotUsingTheRealJournalFolder() {
        #expect(StorageRoot.isRunningTests())
        #expect(StorageRoot.url.path.contains("DearDiary-Tests-"))
        #expect(!StorageRoot.url.path.hasSuffix("/Documents/Freewrite"))
    }
}
