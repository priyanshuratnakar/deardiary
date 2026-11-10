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
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"

    /// The app always uses the shared settings. Tests pass in a throwaway copy.
    init(settings: AISettings = .shared) {
        self.settings = settings
    }

    @State private var keyDraft = ""
    @State private var keyNote: String? = nil
    @State private var testReply = ""
    @State private var testNote: String? = nil
    @State private var isTesting = false
    @State private var testTask: Task<Void, Never>? = nil

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
            testSection
        }
        .frame(width: 440)
        .background(backgroundColor)
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
