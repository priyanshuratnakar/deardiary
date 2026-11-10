//
//  StorageRoot.swift
//  Dear Diary
//
//  The one place that decides which folder the journal lives in.
//
//  Normal runs use Documents/Freewrite, exactly as freewrite always has.
//  Tests and development runs are pointed somewhere else, so the real
//  journal is never read or changed by anything except normal use.
//

import Foundation

enum StorageRoot {
    /// Set this environment variable to run the app against a different journal folder.
    /// The app is sandboxed, so the folder has to be inside the app's own container
    /// (for example its temporary folder).
    static let overrideVariable = "DEARDIARY_STORAGE_ROOT"

    /// The journal folder for this run of the app. Decided once, at launch.
    static let url: URL = resolve()

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        // 1. An explicit override always wins.
        if let override = environment[overrideVariable], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }

        // 2. Tests start the whole app. Give every test run its own throwaway folder.
        if isRunningTests(environment: environment) {
            return temporaryDirectory
                .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("Freewrite", isDirectory: true)
        }

        // 3. Normal use: the same folder freewrite has always used.
        return documentsDirectory.appendingPathComponent("Freewrite")
    }

    /// True when the app was started by Xcode's test runner.
    static func isRunningTests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}
