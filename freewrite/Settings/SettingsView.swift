//
//  SettingsView.swift
//  Dear Diary
//
//  The small Settings window, opened from the app menu (Settings…, ⌘,).
//  Nothing here appears on the writing page.
//
//  It borrows freewrite's look: system 13pt text, grey words that darken on
//  hover, thin dividers, and the page's own white or black background.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings: AISettings
    @ObservedObject private var memoryStatus: MemoryStatus
    private let memoryActions: MemoryActions
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"

    /// The app always uses the shared settings and the real memory engine.
    /// Tests pass in throwaway copies.
    init(
        settings: AISettings = .shared,
        memoryStatus: MemoryStatus = MemoryEngine.shared.status,
        memoryActions: MemoryActions = .live
    ) {
        self.settings = settings
        self.memoryStatus = memoryStatus
        self.memoryActions = memoryActions
    }

    @State private var keyDraft = ""
    @State private var keyNote: String? = nil
    @State private var testReply = ""
    @State private var testNote: String? = nil
    @State private var isTesting = false
    @State private var testTask: Task<Void, Never>? = nil
    /// Set while asking "really rebuild?", to the number of entries it would send.
    @State private var rebuildCount: Int? = nil
    @State private var confirmingForget = false

    // MARK: - Colours, matched to ContentView

    private var isLight: Bool { colorSchemeString != "dark" }
    private var quietColor: Color { isLight ? .gray : .gray.opacity(0.8) }
    private var strongColor: Color { isLight ? .black : .white }
    private var bodyColor: Color {
        isLight ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9)
    }
    private var backgroundColor: Color { isLight ? .white : .black }
    private var hintColor: Color { isLight ? .gray.opacity(0.5) : .gray.opacity(0.6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            aiSection
            Divider()
            keySection
            Divider()
            modelSection
            Divider()
            memorySection
            Divider()
            testSection
        }
        .frame(width: 440)
        .background(backgroundColor)
        .onAppear {
            memoryActions.refresh()
        }
        .onDisappear {
            testTask?.cancel()
        }
    }

    // MARK: - AI on or off

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsWordButton(
                title: settings.aiEnabled ? "AI is On" : "AI is Off",
                quietColor: quietColor,
                strongColor: strongColor
            ) {
                settings.aiEnabled.toggle()
            }

            Text("Your entries and memory are stored only on this Mac, but when AI is on, talking and building memory send entry text to Claude through your API key; with AI off, nothing is sent anywhere.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - API key

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.hasAPIKey {
                HStack(spacing: 8) {
                    Text("API key saved in your Mac's Keychain")
                        .font(.system(size: 13))
                        .foregroundColor(bodyColor)
                    Spacer()
                    SettingsWordButton(title: "Remove", quietColor: quietColor, strongColor: strongColor) {
                        settings.removeAPIKey()
                        keyNote = nil
                    }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField(
                        "API key",
                        text: $keyDraft,
                        prompt: Text("Paste your Claude API key").foregroundColor(hintColor)
                    )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(bodyColor)
                        .onSubmit(saveKey)
                    SettingsWordButton(
                        title: "Save",
                        quietColor: quietColor,
                        strongColor: strongColor,
                        isDisabled: keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: saveKey
                    )
                }
            }

            if let keyNote {
                Text(keyNote)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func saveKey() {
        if settings.saveAPIKey(keyDraft) {
            keyDraft = ""
            keyNote = nil
        } else {
            keyNote = "The key could not be saved to the Keychain."
        }
    }

    // MARK: - Models

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            modelRow(label: "Talk model", text: $settings.talkModel, placeholder: AISettings.defaultTalkModel)
            modelRow(label: "Memory model", text: $settings.digestModel, placeholder: AISettings.defaultDigestModel)

            Text("Use a model name from Anthropic's model list. Leave a field blank to use the default.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func modelRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(quietColor)
                .frame(width: 110, alignment: .leading)
            TextField(label, text: text, prompt: Text(placeholder).foregroundColor(hintColor))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(bodyColor)
                .autocorrectionDisabled()
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsWordButton(
                title: settings.memoryEnabled ? "Memory is On" : "Memory is Off",
                quietColor: quietColor,
                strongColor: strongColor
            ) {
                settings.memoryEnabled.toggle()
                rebuildCount = nil
                confirmingForget = false
            }

            Text("When memory is on, each entry is sent to Claude once after you have finished with it, and what it learns is saved as notes in your memory folder. Talk works without it.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let line = memoryLine {
                Text(line)
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let problem = memoryStatus.summary.problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rebuildCount {
                confirmation(
                    "This sends \(rebuildCount) \(rebuildCount == 1 ? "entry" : "entries") to Claude and replaces what it has learned. Your fixes are kept.",
                    confirm: "Start rebuild",
                    onConfirm: {
                        self.rebuildCount = nil
                        memoryActions.rebuild()
                    },
                    onCancel: { self.rebuildCount = nil }
                )
            } else if confirmingForget {
                confirmation(
                    "This deletes the memory folder, including your fixes, and turns memory off. Your entries are not touched.",
                    confirm: "Forget now",
                    onConfirm: {
                        confirmingForget = false
                        settings.memoryEnabled = false
                        memoryActions.forget()
                    },
                    onCancel: { confirmingForget = false }
                )
            } else {
                HStack(spacing: 8) {
                    if memoryStatus.summary.isWorking {
                        SettingsWordButton(title: "Stop", quietColor: quietColor, strongColor: strongColor) {
                            memoryActions.stop()
                        }
                    } else {
                        SettingsWordButton(
                            title: "Rebuild memory",
                            quietColor: quietColor,
                            strongColor: strongColor,
                            isDisabled: !(settings.aiEnabled && settings.memoryEnabled && settings.hasAPIKey)
                        ) {
                            Task { @MainActor in
                                rebuildCount = await memoryActions.countForRebuild()
                            }
                        }
                    }
                    Text("•").foregroundColor(.gray)
                    SettingsWordButton(title: "Open memory folder", quietColor: quietColor, strongColor: strongColor) {
                        memoryActions.openFolder()
                    }
                }

                SettingsWordButton(title: "Forget everything the AI has learned", quietColor: quietColor, strongColor: strongColor) {
                    confirmingForget = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// One line on what memory holds or is doing, or nil when there is nothing to say.
    private var memoryLine: String? {
        let summary = memoryStatus.summary
        if summary.isWorking {
            return "Reading entry \(min(summary.workDone + 1, summary.workTotal)) of \(summary.workTotal)…"
        }
        let waiting = summary.waitingEntries == 0
            ? nil
            : "\(summary.waitingEntries) \(summary.waitingEntries == 1 ? "entry" : "entries") waiting"
        if summary.thoughts > 0 || summary.digestedEntries > 0 {
            let held = "\(summary.thoughts) \(summary.thoughts == 1 ? "thought" : "thoughts") from \(summary.digestedEntries) \(summary.digestedEntries == 1 ? "entry" : "entries")"
            return waiting.map { "\(held). \($0)." } ?? "\(held)."
        }
        guard settings.memoryEnabled else { return nil }
        return waiting.map { "\($0)." } ?? "Nothing in memory yet."
    }

    /// A question asked in place, with a word to go ahead and a word to back out.
    private func confirmation(_ question: String, confirm: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.system(size: 13))
                .foregroundColor(bodyColor)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SettingsWordButton(title: confirm, quietColor: quietColor, strongColor: strongColor, action: onConfirm)
                Text("•").foregroundColor(.gray)
                SettingsWordButton(title: "Cancel", quietColor: quietColor, strongColor: strongColor, action: onCancel)
            }
        }
    }

    // MARK: - Test connection

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsWordButton(
                title: isTesting ? "Testing…" : "Test connection",
                quietColor: quietColor,
                strongColor: strongColor,
                isDisabled: isTesting,
                action: runTest
            )

            if !testReply.isEmpty {
                Text(testReply)
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let testNote {
                Text(testNote)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Sends one fixed, harmless message (no journal text) and shows the reply as it arrives.
    private func runTest() {
        testTask?.cancel()
        testReply = ""
        testNote = nil
        isTesting = true

        let request = LLMRequest(
            model: settings.resolvedTalkModel,
            system: Prompts.connectionTestSystem,
            messages: [LLMMessage(role: .user, text: Prompts.connectionTest)],
            maxTokens: AILimits.connectionTestMaxTokens
        )

        testTask = Task { @MainActor in
            do {
                for try await piece in AnthropicProvider.shared.stream(request) {
                    testReply += piece
                }
                if testReply.isEmpty {
                    testNote = "Claude answered with nothing. Try again."
                }
            } catch is CancellationError {
                // The window closed or a new test started. Nothing to show.
            } catch {
                testReply = ""
                testNote = ((error as? LLMError) ?? .unexpected).userMessage
            }
            isTesting = false
        }
    }
}

/// What the memory words in Settings do. Tests pass in versions that do nothing.
struct MemoryActions {
    var refresh: () -> Void
    var countForRebuild: () async -> Int
    var rebuild: () -> Void
    var stop: () -> Void
    var forget: () -> Void
    var openFolder: () -> Void

    static let live = MemoryActions(
        refresh: { Task { await MemoryEngine.shared.refreshStatus() } },
        countForRebuild: { await MemoryEngine.shared.entriesToRebuild() },
        rebuild: { Task { await MemoryEngine.shared.rebuild() } },
        stop: { Task { await MemoryEngine.shared.stop() } },
        forget: { Task { await MemoryEngine.shared.forgetEverything() } },
        openFolder: { NSWorkspace.shared.open(MemoryStore().ensureFolder()) }
    )

    static let none = MemoryActions(
        refresh: {},
        countForRebuild: { 0 },
        rebuild: {},
        stop: {},
        forget: {},
        openFolder: {}
    )
}

/// A word you can click, in the same style as freewrite's bottom bar:
/// grey by default, darker on hover, with a pointing-hand cursor.
private struct SettingsWordButton: View {
    let title: String
    let quietColor: Color
    let strongColor: Color
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundColor(isHovering && !isDisabled ? strongColor : quietColor)
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
