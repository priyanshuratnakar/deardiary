//
//  Prompts.swift
//  Dear Diary
//
//  Every prompt the app sends to the AI lives in this file, so the wording can
//  be read and edited in one place. Talk, digest and consolidate prompts will
//  be added here as those features arrive.
//

import Foundation

enum Prompts {
    // MARK: - Settings: Test connection

    /// Sent by the "Test connection" button in Settings.
    /// It contains no journal text and nothing about the user.
    static let connectionTestSystem = "You are being used to check that a journaling app can reach you. Keep the reply to one short sentence."

    static let connectionTest = "Say a brief, warm hello to confirm the connection works."
}
