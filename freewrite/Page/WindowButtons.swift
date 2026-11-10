//
//  WindowButtons.swift
//  Dear Diary
//
//  The red, yellow and green buttons at the top left of the journal window.
//
//  freewrite hid them. Dear Diary shows them, and lets them step back with the
//  bottom bar: while a timed session has faded the bar out, or the video
//  recorder is up, they fade out too, so the page stays bare. They come back
//  when the bar does, and whenever the pointer is over the top strip of the
//  window, which is where anyone looking for them would go.
//
//  In fullscreen macOS looks after them itself, and they are left alone.
//

import AppKit
import SwiftUI

@MainActor
final class WindowButtons: NSObject {
    static let shared = WindowButtons()

    private weak var window: NSWindow?
    private weak var strip: NSView?
    private var tracking: NSTrackingArea?

    /// The bar has faded out, or the video recorder is up.
    private(set) var isQuiet = false
    /// The pointer is over the top strip of the window.
    private(set) var pointerIsOverStrip = false

    /// Whether the buttons should show. Kept apart from the window so it can be checked by itself.
    static func shouldShow(isQuiet: Bool, pointerIsOverStrip: Bool, isFullscreen: Bool) -> Bool {
        isFullscreen || !isQuiet || pointerIsOverStrip
    }

    /// Tells the buttons which window they belong to. Windows without them (pictures drawn off screen) are passed over.
    func attach(to window: NSWindow?) {
        guard let window, window !== self.window, window.standardWindowButton(.closeButton) != nil else { return }
        self.window = window
        watchStrip()

        let center = NotificationCenter.default
        center.removeObserver(self)
        center.addObserver(self, selector: #selector(fullscreenChanged), name: NSWindow.didEnterFullScreenNotification, object: window)
        center.addObserver(self, selector: #selector(fullscreenChanged), name: NSWindow.didExitFullScreenNotification, object: window)
        apply(animated: false)
    }

    /// Called when the bar fades out or comes back.
    func setQuiet(_ quiet: Bool) {
        guard quiet != isQuiet else { return }
        isQuiet = quiet
        apply(animated: true)
    }

    /// The three buttons of the window in use, for the checks in the tests.
    var buttons: [NSButton] {
        guard let window else { return [] }
        return [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
    }

    private var shouldShowNow: Bool {
        Self.shouldShow(
            isQuiet: isQuiet,
            pointerIsOverStrip: pointerIsOverStrip,
            isFullscreen: window?.styleMask.contains(.fullScreen) ?? false
        )
    }

    private func apply(animated: Bool) {
        let show = shouldShowNow
        let buttons = self.buttons
        guard !buttons.isEmpty else { return }

        if show {
            // Hidden buttons take no clicks, so they are brought back before they fade in.
            buttons.forEach { $0.isHidden = false }
        }
        NSAnimationContext.runAnimationGroup({ context in
            // Out slowly with the bar, back quickly.
            context.duration = animated ? (show ? 0.2 : 1.0) : 0
            buttons.forEach { $0.animator().alphaValue = show ? 1 : 0 }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                // Only once they are fully out, and only if nothing has changed meanwhile.
                guard let self, !self.shouldShowNow else { return }
                self.buttons.forEach { $0.isHidden = true }
            }
        })
    }

    /// Watches the strip the buttons sit in, so they can come back when the pointer goes looking for them.
    private func watchStrip() {
        if let tracking, let strip {
            strip.removeTrackingArea(tracking)
        }
        guard let strip = window?.standardWindowButton(.closeButton)?.superview else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        strip.addTrackingArea(area)
        self.strip = strip
        self.tracking = area
    }

    @objc func mouseEntered(with event: NSEvent) {
        pointerIsOverStrip = true
        apply(animated: true)
    }

    @objc func mouseExited(with event: NSEvent) {
        pointerIsOverStrip = false
        apply(animated: true)
    }

    @objc private func fullscreenChanged() {
        apply(animated: false)
    }
}

/// Lets the window buttons follow the bottom bar. `ContentView` adds this once.
struct WindowButtonsFollowBar: ViewModifier {
    /// True while the bar is faded out or the video recorder is up.
    let isQuiet: Bool

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window in
                WindowButtons.shared.attach(to: window)
            })
            .onChange(of: isQuiet) { _, quiet in
                WindowButtons.shared.setQuiet(quiet)
            }
    }
}

/// Finds the window a view is in.
private struct WindowReader: NSViewRepresentable {
    let found: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        report(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        report(view)
    }

    /// The view joins its window a moment after it is made, so the answer is read on the next turn.
    private func report(_ view: NSView) {
        let found = self.found
        Task { @MainActor in
            found(view.window)
        }
    }
}
