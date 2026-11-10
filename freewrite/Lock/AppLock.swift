//
//  AppLock.swift
//  Dear Diary
//
//  The lock: when it closes, when it opens, and what Settings may change.
//
//  The lock is on from the first launch (see LockSettings.swift), until it is
//  turned off in Settings.
//
//  With the lock on, Dear Diary opens locked. It locks again when the Mac
//  sleeps, when its screen locks or sleeps, when another user takes over the
//  Mac, when Dear Diary has been in the background for the chosen number of
//  minutes, and when "Lock now" is clicked. It opens only when macOS says the
//  person at the Mac is its owner (see Authenticator.swift).
//
//  What the lock is and is not: it covers Dear Diary's windows. The entries
//  stay plain files in the journal folder, as the PRD asks, protected by the
//  Mac's own login. The lock does not encrypt anything.
//
//  Background work (memory, versions) carries on while locked. It reads files,
//  not the screen.
//

import AppKit
import Combine
import Foundation

@MainActor
final class AppLock: ObservableObject {
    /// The app's lock.
    static let shared = AppLock()

    /// True while the windows are covered.
    @Published private(set) var isLocked: Bool
    /// True while macOS is showing its sheet.
    @Published private(set) var isAsking = false
    /// One plain line when something went wrong, otherwise nil.
    @Published private(set) var problem: String? = nil

    let settings: LockSettings
    private let authenticator: Authenticator
    private let now: () -> Date

    /// When Dear Diary went to the background, if it is there now.
    private var awaySince: Date? = nil
    private var awayTimer: Timer? = nil
    /// True when the next sight of the locked window should ask macOS without waiting for a
    /// click: at launch, and when coming back to a diary that locked while it was in the
    /// background. Never straight after "Lock now", and never straight after the sheet was
    /// closed, so a closed sheet does not come back by itself.
    private var asksByItself: Bool
    private var isInBackground = false
    private var observers: [NSObjectProtocol] = []

    enum Line {
        static let reasonToUnlock = "unlock your journal"
        static let reasonToSwitchOn = "turn on the lock"
        static let reasonToSwitchOff = "turn off the lock"
        static let failed = "Couldn't check that it's you. Try again."
        static let unavailable = "The lock needs a password on this Mac. Set one in System Settings, then turn the lock on."
    }

    /// - Parameter watchesTheMac: false in tests, which call the events themselves.
    init(
        settings: LockSettings = .shared,
        authenticator: Authenticator = DeviceOwnerAuthenticator(),
        now: @escaping () -> Date = { Date() },
        watchesTheMac: Bool = true
    ) {
        self.settings = settings
        self.authenticator = authenticator
        self.now = now
        // A Mac that cannot check its owner (it has no password) has no way to open a lock,
        // so the lock stays open there.
        let opensLocked = settings.enabled && authenticator.isAvailable()
        self.isLocked = opensLocked
        self.asksByItself = opensLocked
        if watchesTheMac {
            watch()
        }
    }

    // MARK: - Opening

    /// Asks macOS to check who is there, and opens if it is the owner.
    func unlock() async {
        guard isLocked, !isAsking else { return }
        isAsking = true
        asksByItself = false
        let result = await authenticator.authenticate(reason: Line.reasonToUnlock)
        isAsking = false

        switch result {
        case .allowed:
            open()
        case .cancelled:
            break
        case .failed:
            problem = Line.failed
        case .unavailable:
            // A Mac with no password cannot be checked, and has nothing a lock could add to.
            // Staying shut would only keep the owner out.
            open()
            problem = Line.unavailable
        }
    }

    /// Asks without waiting for a click, if this is one of the moments for it. Called when
    /// the locked window comes into view and when Dear Diary comes back to the front.
    func askIfJustLocked() {
        guard isLocked, asksByItself, !isAsking else { return }
        Task { await unlock() }
    }

    private func open() {
        isLocked = false
        problem = nil
        awaySince = nil
        awayTimer?.invalidate()
        awayTimer = nil
    }

    // MARK: - Closing

    /// "Lock now" in Settings.
    func lockNow() {
        close()
    }

    private func close() {
        guard settings.enabled, !isLocked else { return }
        isLocked = true
        // Locked while away: ask on the way back. Locked while in front: wait for a click.
        asksByItself = isInBackground
        problem = nil
        // Whatever was being typed into loses the keyboard, so nothing typed while locked lands on the page.
        NSApp?.windows.forEach { $0.makeFirstResponder(nil) }
    }

    /// The Mac went to sleep, its screen locked or slept, or another user took over.
    func macSteppedAway() {
        close()
    }

    /// Dear Diary went to the background.
    func appWentToBackground() {
        isInBackground = true
        guard settings.enabled else { return }
        if isLocked {
            // Coming back to a locked diary asks once. Not if this trip to the background
            // is only macOS showing its own sheet.
            if !isAsking {
                asksByItself = true
            }
            return
        }
        awaySince = now()
        awayTimer?.invalidate()
        // Locks while still in the background, so the window is covered even if nobody comes back to it.
        awayTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.afterMinutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.lockIfAwayTooLong() }
        }
    }

    /// Dear Diary came back to the front.
    func appCameBack() {
        lockIfAwayTooLong()
        isInBackground = false
        awaySince = nil
        awayTimer?.invalidate()
        awayTimer = nil
        askIfJustLocked()
    }

    /// Locks if Dear Diary has been in the background for the chosen time. Safe to call at any moment.
    func lockIfAwayTooLong() {
        guard let awaySince, now().timeIntervalSince(awaySince) >= TimeInterval(settings.afterMinutes * 60) else { return }
        close()
    }

    // MARK: - Settings

    /// Turns the lock on or off. Both ask macOS first.
    ///
    /// Turning it off asks so that only the Mac's owner can. Turning it on asks so that the
    /// check is seen to work, on this Mac, before the lock can ever close: if the sheet does
    /// not appear or does not pass, the lock stays off and nobody is locked out.
    func setEnabled(_ on: Bool) async {
        guard on != settings.enabled, !isAsking else { return }
        if on {
            guard authenticator.isAvailable() else {
                problem = Line.unavailable
                return
            }
            isAsking = true
            let result = await authenticator.authenticate(reason: Line.reasonToSwitchOn)
            isAsking = false
            switch result {
            case .allowed:
                problem = nil
                settings.enabled = true
            case .cancelled:
                break
            case .failed:
                problem = Line.failed
            case .unavailable:
                problem = Line.unavailable
            }
            return
        }

        isAsking = true
        let result = await authenticator.authenticate(reason: Line.reasonToSwitchOff)
        isAsking = false
        switch result {
        case .allowed, .unavailable:
            settings.enabled = false
            open()
        case .cancelled:
            break
        case .failed:
            problem = Line.failed
        }
    }

    // MARK: - Watching the Mac

    private func watch() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.macSteppedAway() }
            })
        }
        // Posted by macOS when the screen is locked from the Apple menu or by a hot corner.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.macSteppedAway() }
        })

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appWentToBackground() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appCameBack() }
        })
    }
}
