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
    @ObservedObject private var versions: VersionSettings
    @ObservedObject private var versionIndex: VersionIndex
    private let versionActions: VersionActions
    @ObservedObject private var catalog: ModelCatalog
    /// What "Test connection" talks to. Tests pass a pretend service.
    private let connection: LLMProvider
    @ObservedObject private var journalImport: JournalImport
    @ObservedObject private var lock: AppLock
    @ObservedObject private var lockSettings: LockSettings
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"

    /// The app always uses the shared settings and the real memory engine.
    /// Tests pass in throwaway copies.
    @MainActor
    init(
        settings: AISettings = .shared,
        memoryStatus: MemoryStatus = MemoryEngine.shared.status,
        memoryActions: MemoryActions = .live,
        versions: VersionSettings = .shared,
        versionIndex: VersionIndex = SnapshotKeeper.shared.index,
        versionActions: VersionActions = .live,
        catalog: ModelCatalog? = nil,
        connection: LLMProvider = AIRouter.shared,
        journalImport: JournalImport? = nil,
        lock: AppLock? = nil
    ) {
        self.settings = settings
        self.memoryStatus = memoryStatus
        self.memoryActions = memoryActions
        self.versions = versions
        self.versionIndex = versionIndex
        self.versionActions = versionActions
        self.catalog = catalog ?? .shared
        self.connection = connection
        self.journalImport = journalImport ?? .shared
        let lock = lock ?? .shared
        self.lock = lock
        self.lockSettings = lock.settings
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
    /// Goes up each time the model list should be asked for again ("Check again", a new address).
    @State private var refreshCount = 0

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
            providerSection
            Divider()
            modelSection
            Divider()
            memorySection
            Divider()
            testSection
            Divider()
            versionsSection
            Divider()
            lockSection
            Divider()
            movingInSection
        }
        .frame(width: 440)
        .background(backgroundColor)
        .onAppear {
            memoryActions.refresh()
        }
        .onDisappear {
            testTask?.cancel()
        }
        // The model list is asked for whenever what it depends on changes, and never while AI is off.
        .task(id: setupKey) {
            await catalog.refresh(for: settings)
        }
        // A result from an earlier test says nothing about the settings as they are now.
        .onChange(of: setupKey + "|" + settings.talkModel) { _, _ in
            clearTest()
        }
    }

    /// Changes whenever the service, its key, its address or AI itself changes.
    private var setupKey: String {
        "\(settings.aiEnabled)|\(settings.provider.rawValue)|\(settings.hasAPIKey)|\(AISettings.address(from: settings.otherBaseURL) != nil)|\(refreshCount)"
    }

    private func clearTest() {
        testTask?.cancel()
        testTask = nil
        isTesting = false
        testReply = ""
        testNote = nil
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

            Text("Your entries and memory are stored only on this Mac. With AI off, nothing is sent anywhere.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Which service

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Runs on")
                    .font(.system(size: 13))
                    .foregroundColor(quietColor)
                    .frame(width: 110, alignment: .leading)
                ForEach(Array(AIProviderKind.allCases.enumerated()), id: \.offset) { index, kind in
                    if index > 0 {
                        Text("•").foregroundColor(.gray)
                    }
                    // The chosen service is dark; the others are grey words.
                    SettingsWordButton(
                        title: kind.title,
                        quietColor: settings.provider == kind ? strongColor : quietColor,
                        strongColor: strongColor
                    ) {
                        choose(kind)
                    }
                }
            }

            Text(Self.description(of: settings.provider))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch settings.provider {
            case .local:
                localStatus
            case .openai, .claude:
                keyRow
            case .other:
                addressRow
                keyRow
            }

            if let keyNote {
                Text(keyNote)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if settings.aiEnabled, let missing = missingLine(for: [.key, .address]) {
                Text(missing)
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    static func description(of kind: AIProviderKind) -> String {
        switch kind {
        case .local:
            return "A free open model that runs on this Mac through Ollama. Nothing you write leaves this Mac."
        case .openai:
            return "OpenAI, through your own API key. Entry text is sent to OpenAI when you talk or build memory. A ChatGPT plan does not include this."
        case .claude:
            return "Claude, through your own API key from Anthropic. Entry text is sent to Anthropic when you talk or build memory."
        case .other:
            return "Any service that speaks the OpenAI chat format, at an address you give. Entry text is sent to that address when you talk or build memory."
        }
    }

    private func choose(_ kind: AIProviderKind) {
        guard settings.provider != kind else { return }
        keyDraft = ""
        keyNote = nil
        catalog.clear()
        settings.provider = kind
    }

    /// One plain line saying what is still needed, if it is one of the given things.
    private func missingLine(for gaps: [AISetupGap]) -> String? {
        guard let gap = settings.setupGap, gaps.contains(gap) else { return nil }
        switch gap {
        case .key:
            return "Add a key to use Talk and Memory."
        case .address:
            return "Add an address to use Talk and Memory."
        case .model:
            return "Choose a model to use Talk and Memory."
        }
    }

    // MARK: - On this Mac

    @ViewBuilder
    private var localStatus: some View {
        if !settings.aiEnabled {
            EmptyView()
        } else {
            switch catalog.state {
            case .idle, .loading:
                Text("Looking for Ollama…")
                    .font(.system(size: 13))
                    .foregroundColor(hintColor)
            case .loaded(let models) where models.isEmpty:
                Text("Ollama is running, but it has no models yet. Download one in the Ollama app, then check again.")
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsWordButton(title: "Check again", quietColor: quietColor, strongColor: strongColor) {
                    refreshCount += 1
                }
            case .loaded(let models):
                Text("Ollama is running. \(models.count) \(models.count == 1 ? "model" : "models") found.")
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
            case .failed(let error):
                Text(error.userMessage(for: .local))
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    SettingsWordButton(title: "Check again", quietColor: quietColor, strongColor: strongColor) {
                        refreshCount += 1
                    }
                    Text("•").foregroundColor(.gray)
                    SettingsWordButton(title: "Get Ollama", quietColor: quietColor, strongColor: strongColor) {
                        if let url = URL(string: "https://ollama.com/download") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    // MARK: - A key and an address

    private var keyRow: some View {
        Group {
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
                        prompt: Text(keyPrompt).foregroundColor(hintColor)
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
        }
    }

    private var keyPrompt: String {
        settings.provider == .other
            ? "API key, if the service needs one"
            : "Paste your \(settings.provider.title) API key"
    }

    private func saveKey() {
        if settings.saveAPIKey(keyDraft) {
            keyDraft = ""
            keyNote = nil
            refreshCount += 1
        } else {
            keyNote = "Couldn't save the key to your Keychain."
        }
    }

    private var addressRow: some View {
        HStack(spacing: 8) {
            Text("Address")
                .font(.system(size: 13))
                .foregroundColor(quietColor)
                .frame(width: 110, alignment: .leading)
            TextField("Address", text: $settings.otherBaseURL, prompt: Text("http://localhost:1234/v1").foregroundColor(hintColor))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(bodyColor)
                .autocorrectionDisabled()
                .onSubmit { refreshCount += 1 }
        }
    }

    // MARK: - Models

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typesModelNames {
                typedModelRow(label: "Talk model", text: $settings.talkModel)
                typedModelRow(label: "Memory model", text: $settings.digestModel)
            } else {
                ModelPickerRow(label: "Talk model", selection: $settings.talkModel, choices: catalog.choices, waiting: waitingForModels, isLight: isLight)
                ModelPickerRow(label: "Memory model", selection: $settings.digestModel, choices: catalog.choices, waiting: waitingForModels, isLight: isLight)
            }

            Text(modelNote)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case .failed(let error) = catalog.state, settings.provider != .local, !typesModelNames {
                Text(error.userMessage(for: settings.provider))
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsWordButton(title: "Check again", quietColor: quietColor, strongColor: strongColor) {
                    refreshCount += 1
                }
            }

            if settings.aiEnabled, waitingForModels == nil || typesModelNames, let missing = missingLine(for: [.model]) {
                Text(missing)
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// What stands in for the list while a model cannot be picked, or nil when it can.
    private var waitingForModels: String? {
        guard settings.aiEnabled else { return "Turn AI on first" }
        switch settings.setupGap {
        case .key: return "Add a key first"
        case .address: return "Add an address first"
        default: break
        }
        switch catalog.state {
        case .idle, .loading:
            return "Loading models…"
        case .failed:
            return "Not available"
        case .loaded(let models):
            return models.isEmpty ? "No models found" : nil
        }
    }

    /// "Other" services do not always list their models. When one does not, the name is typed.
    private var typesModelNames: Bool {
        guard settings.provider == .other, settings.aiEnabled, settings.setupGap != .address else { return false }
        switch catalog.state {
        // The service answered, but has no list to give.
        case .failed(let error): return error == .modelNotFound || error == .unexpected
        case .loaded(let models): return models.isEmpty
        default: return false
        }
    }

    private var modelNote: String {
        if typesModelNames {
            return "This service did not list its models, so type the model's name as the service writes it."
        }
        switch settings.provider {
        case .local:
            return "Chosen from the models installed in Ollama on this Mac."
        default:
            return "Chosen from the models \(settings.provider.serviceNameInline) offers."
        }
    }

    private func typedModelRow(label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(quietColor)
                .frame(width: 110, alignment: .leading)
            TextField(label, text: text, prompt: Text("Model name").foregroundColor(hintColor))
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

            Text("When memory is on, each entry is read once by the AI after you have finished with it, and what it learns is saved as notes in your memory folder. Talk works without it.")
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

            if let lastTidy = memoryStatus.summary.lastTidy {
                Text(lastTidy)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rebuildCount {
                confirmation(
                    "This has the AI read \(rebuildCount) \(rebuildCount == 1 ? "entry" : "entries") again and replaces what it has learned. Your fixes are kept.",
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
                            isDisabled: !(settings.isReady && settings.memoryEnabled)
                        ) {
                            Task { @MainActor in
                                rebuildCount = await memoryActions.countForRebuild()
                            }
                        }
                    }
                    Text("•").foregroundColor(.gray)
                    SettingsWordButton(
                        title: "Tidy memory now",
                        quietColor: quietColor,
                        strongColor: strongColor,
                        isDisabled: memoryStatus.summary.isWorking || !(settings.isReady && settings.memoryEnabled)
                    ) {
                        memoryActions.tidy()
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
                isDisabled: isTesting || !settings.isReady,
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

    // MARK: - Versions

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsWordButton(
                title: versions.enabled ? "Versions are On" : "Versions are Off",
                quietColor: quietColor,
                strongColor: strongColor
            ) {
                versions.enabled.toggle()
                versionActions.changed()
            }

            Text("When versions are on, a copy of an entry is kept every five minutes while it changes, so you can read an earlier one and bring it back. Copies stay in your journal folder and are never sent anywhere. They work with AI on or off.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if versions.enabled {
                Text("Open them from the small clock beside an entry in History.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let problem = versionIndex.problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsWordButton(title: "Open versions folder", quietColor: quietColor, strongColor: strongColor) {
                versionActions.openFolder()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - The lock

    private var lockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsWordButton(
                title: lockSettings.enabled ? "Lock is On" : "Lock is Off",
                quietColor: quietColor,
                strongColor: strongColor,
                isDisabled: lock.isAsking
            ) {
                // Turning it off asks macOS first, so only the Mac's owner can.
                Task { await lock.setEnabled(!lockSettings.enabled) }
            }

            Text("When the lock is on, Dear Diary opens locked and asks for Touch ID or your Mac password. It locks again when your Mac sleeps and when it has been in the background for a while.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if lockSettings.enabled {
                HStack(spacing: 8) {
                    SettingsWordButton(title: "Lock now", quietColor: quietColor, strongColor: strongColor) {
                        lock.lockNow()
                    }
                    Text("•").foregroundColor(.gray)
                    Text("Lock after")
                        .font(.system(size: 13))
                        .foregroundColor(quietColor)
                    // Each click steps to the next choice.
                    SettingsWordButton(title: lockSettings.delayInWords, quietColor: bodyColor, strongColor: strongColor) {
                        lockSettings.stepDelay()
                    }
                }

                Text("The lock covers Dear Diary's windows. Your entries stay plain files in your journal folder, protected by your Mac's own login.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let problem = lock.problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Bringing entries from freewrite

    private var movingInSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsWordButton(
                title: "Bring entries from freewrite…",
                quietColor: quietColor,
                strongColor: strongColor,
                isDisabled: !journalImport.canChoose
            ) {
                Task { await journalImport.choose() }
            }

            Text("If you used freewrite before, pick its folder and your entries are copied into Dear Diary. The originals are left where they are.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let line = journalImport.line {
                Text(line)
                    .font(.system(size: 13))
                    .foregroundColor(bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch journalImport.state {
            case .found:
                HStack(spacing: 8) {
                    SettingsWordButton(title: journalImport.copyWord ?? "Copy", quietColor: quietColor, strongColor: strongColor) {
                        journalImport.copy()
                    }
                    Text("•").foregroundColor(.gray)
                    SettingsWordButton(title: "Cancel", quietColor: quietColor, strongColor: strongColor) {
                        journalImport.cancel()
                    }
                }
            case .copying:
                SettingsWordButton(title: "Stop", quietColor: quietColor, strongColor: strongColor) {
                    journalImport.stop()
                }
            case .done(let copied, _, _) where copied > 0:
                Text("The AI has not read them. To include them in memory, use Rebuild memory above; it shows the count first.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
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

        let kind = settings.provider
        let connection = self.connection
        let request = LLMRequest(
            model: settings.resolvedTalkModel,
            system: Prompts.connectionTestSystem,
            messages: [LLMMessage(role: .user, text: Prompts.connectionTest)],
            maxTokens: AILimits.connectionTestMaxTokens
        )

        testTask = Task { @MainActor in
            do {
                for try await piece in connection.stream(request) {
                    testReply += piece
                }
                if testReply.isEmpty {
                    testNote = "\(kind.serviceName) answered with nothing. Try again."
                }
            } catch is CancellationError {
                // The window closed or a new test started. Nothing to show.
            } catch {
                testReply = ""
                testNote = ((error as? LLMError) ?? .unexpected).userMessage(for: kind)
            }
            isTesting = false
        }
    }
}

/// What the versions words in Settings do. Tests pass in ones that do nothing.
struct VersionActions {
    /// Called when versions are switched on or off.
    var changed: () -> Void
    var openFolder: () -> Void

    static let live = VersionActions(
        changed: { SnapshotKeeper.shared.nudge() },
        openFolder: { NSWorkspace.shared.open(SnapshotStore().ensureFolder()) }
    )

    static let none = VersionActions(changed: {}, openFolder: {})
}

/// What the memory words in Settings do. Tests pass in versions that do nothing.
struct MemoryActions {
    var refresh: () -> Void
    var countForRebuild: () async -> Int
    var rebuild: () -> Void
    var tidy: () -> Void
    var stop: () -> Void
    var forget: () -> Void
    var openFolder: () -> Void

    static let live = MemoryActions(
        refresh: { Task { await MemoryEngine.shared.refreshStatus() } },
        countForRebuild: { await MemoryEngine.shared.entriesToRebuild() },
        rebuild: { Task { await MemoryEngine.shared.rebuild() } },
        tidy: { Task { await MemoryEngine.shared.tidy(force: true) } },
        stop: { Task { await MemoryEngine.shared.stop() } },
        forget: { Task { await MemoryEngine.shared.forgetEverything() } },
        openFolder: { NSWorkspace.shared.open(MemoryStore().ensureFolder()) }
    )

    static let none = MemoryActions(
        refresh: {},
        countForRebuild: { 0 },
        rebuild: {},
        tidy: {},
        stop: {},
        forget: {},
        openFolder: {}
    )
}

/// One "Talk model" or "Memory model" line: the chosen model's name, and a list to pick another from.
struct ModelPickerRow: View {
    let label: String
    @Binding var selection: String
    let choices: [AIModelChoice]
    /// What to show while a model cannot be picked ("Add a key first"), or nil when the list is ready.
    let waiting: String?
    let isLight: Bool

    @State private var isOpen = false
    @State private var isHovering = false

    private var quietColor: Color { isLight ? .gray : .gray.opacity(0.8) }
    private var strongColor: Color { isLight ? .black : .white }
    private var bodyColor: Color {
        isLight ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9)
    }
    private var hintColor: Color { isLight ? .gray.opacity(0.5) : .gray.opacity(0.6) }

    /// The chosen model by the name the service gives it, or as saved if the service no longer lists it.
    private var chosenName: String? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return choices.first { $0.id == trimmed }?.name ?? trimmed
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(quietColor)
                .frame(width: 110, alignment: .leading)

            if let waiting {
                Text(chosenName ?? waiting)
                    .font(.system(size: 13))
                    .foregroundColor(hintColor)
            } else {
                Button {
                    isOpen = true
                } label: {
                    HStack(spacing: 5) {
                        Text(chosenName ?? "Choose a model")
                            .font(.system(size: 13))
                            .foregroundColor(isHovering || isOpen ? strongColor : (chosenName == nil ? quietColor : bodyColor))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(quietColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .popover(isPresented: $isOpen, attachmentAnchor: .point(UnitPoint(x: 0.5, y: 1)), arrowEdge: .bottom) {
                    ModelList(choices: choices, selected: selection, isLight: isLight) { id in
                        selection = id
                        isOpen = false
                    }
                }
            }
            Spacer()
        }
    }
}

/// The list that opens under a model's name, in the style of freewrite's Chat pop-up.
struct ModelList: View {
    let choices: [AIModelChoice]
    let selected: String
    let isLight: Bool
    let onPick: (String) -> Void

    private var textColor: Color { isLight ? .primary : .white }

    var body: some View {
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                if index > 0 {
                    Divider()
                }
                Button {
                    onPick(choice.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(choice.name)
                            .font(.system(size: 13))
                        if let detail = choice.detail {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 12)
                        if choice.id == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(textColor)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }

        // A long list (OpenAI offers dozens) scrolls rather than growing past the window.
        Group {
            if choices.count > 9 {
                ScrollView { rows }
                    .frame(height: 300)
            } else {
                rows
            }
        }
        .frame(width: 240)
        .background(isLight ? Color(NSColor.controlBackgroundColor) : Color(NSColor.darkGray))
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
