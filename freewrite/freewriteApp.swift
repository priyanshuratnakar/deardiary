//
//  freewriteApp.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI

@main
struct freewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"
    
    init() {
        // Register Lato font
        if let fontURL = Bundle.main.url(forResource: "Lato-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }

        // Dear Diary: the memory engine checks the journal folder in the background.
        // It does nothing unless AI and memory are both switched on in Settings.
        MemoryEngine.shared.start()

        // Dear Diary: keeps earlier versions of entries in the background.
        // It does nothing unless versions are switched on in Settings.
        SnapshotKeeper.shared.start()
    }
     
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Dear Diary: freewrite hid the window toolbar here, which also hid the red, yellow
                // and green buttons. They show now, and WindowButtons lets them step back with the bar.
                // Dear Diary: the lock covers this window while it is closed. It is off unless switched on in Settings.
                .modifier(LockGate())
                .preferredColorScheme(colorSchemeString == "dark" ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 600)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)

        // Dear Diary: the Settings window, opened from the app menu (Settings…, ⌘,).
        Settings {
            SettingsView()
                // Dear Diary: Settings is covered too while the lock is closed.
                .modifier(LockGate())
                .preferredColorScheme(colorSchemeString == "dark" ? .dark : .light)
        }
    }
}

// Add AppDelegate to handle window configuration
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            // Ensure window starts in windowed mode
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            
            // Center the window on the screen
            window.center()
        }
    }
} 
