//
//  LockScreen.swift
//  Dear Diary
//
//  What a window shows while Dear Diary is locked, and the gate that puts it
//  over a window. Nothing of the journal is on screen behind it: the window's
//  own content is covered, takes no clicks or typing, and is hidden from
//  VoiceOver until the lock opens.
//

import SwiftUI

struct LockScreen: View {
    @ObservedObject var lock: AppLock
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"
    @State private var isHovering = false

    /// The line under the lock. The owner's to edit.
    static let line = "for your eyes only"

    private var isLight: Bool { colorSchemeString != "dark" }
    private var quietColor: Color { isLight ? .gray : .gray.opacity(0.8) }
    private var strongColor: Color { isLight ? .black : .white }
    private var hintColor: Color { isLight ? .gray.opacity(0.5) : .gray.opacity(0.6) }

    var body: some View {
        ZStack {
            Color(isLight ? .white : .black)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                BarIcon(kind: .lock, size: 22)
                    .foregroundColor(quietColor)

                Text(Self.line)
                    .font(.custom("Lato-Regular", size: 18))
                    .foregroundColor(hintColor)

                Button("Unlock") {
                    Task { await lock.unlock() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(lock.isAsking ? hintColor : (isHovering ? strongColor : quietColor))
                .disabled(lock.isAsking)
                // Return unlocks, so the keyboard is enough.
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                if let problem = lock.problem {
                    Text(problem)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }
            }
        }
        .onAppear {
            lock.askIfJustLocked()
        }
    }
}

/// Puts the lock over a window. `freewriteApp` adds it to the journal window and to Settings.
struct LockGate: ViewModifier {
    @ObservedObject private var lock: AppLock

    /// The app uses its own lock. Tests pass one of their own.
    @MainActor
    init(lock: AppLock? = nil) {
        self.lock = lock ?? .shared
    }

    func body(content: Content) -> some View {
        content
            // Covered content must not take clicks or typing, or be read out.
            .disabled(lock.isLocked)
            .accessibilityHidden(lock.isLocked)
            .overlay {
                if lock.isLocked {
                    LockScreen(lock: lock)
                }
            }
    }
}
