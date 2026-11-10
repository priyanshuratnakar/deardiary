//
//  SettingsSnapshotTests.swift
//  freewriteTests
//
//  Draws the Settings window off screen and attaches a picture of it to the
//  test results, so its look can be checked without clicking through the app.
//  It uses throwaway settings, so the real preferences and key are untouched.
//

import XCTest
import SwiftUI
@testable import freewrite

final class SettingsSnapshotTests: XCTestCase {

    @MainActor
    func testSettingsDrawsWithAIOffInLightMode() throws {
        try snapshot(named: "settings-light-ai-off", dark: false) { _ in }
    }

    @MainActor
    func testSettingsDrawsWithAIOnInDarkMode() throws {
        try snapshot(named: "settings-dark-ai-on", dark: true) { settings in
            settings.aiEnabled = true
            settings.saveAPIKey("made-up-key-for-tests")
        }
    }

    @MainActor
    private func snapshot(named name: String, dark: Bool, configure: (AISettings) -> Void) throws {
        let suiteName = "deardiary.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keychain = Keychain(service: "com.priyanshuratnakar.deardiary.tests.\(UUID().uuidString)", account: "test")
        defer {
            keychain.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(dark ? "dark" : "light", forKey: "colorScheme")
        let settings = AISettings(defaults: defaults, keychain: keychain)
        configure(settings)

        let view = SettingsView(settings: settings)
            .defaultAppStorage(defaults)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)

        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(bitmap)

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
