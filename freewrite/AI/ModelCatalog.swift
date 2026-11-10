//
//  ModelCatalog.swift
//  Dear Diary
//
//  The list of models the chosen service offers, for the pickers in Settings.
//  It is fetched from the service itself, so a model's name is picked, never
//  typed. Nothing is fetched while AI is off or the service is not set up.
//

import Foundation
import Combine

@MainActor
final class ModelCatalog: ObservableObject {
    enum State: Equatable {
        /// Nothing has been asked for: AI is off, or a key or an address is still missing.
        case idle
        case loading
        case loaded([AIModelChoice])
        /// The list could not be fetched, and why.
        case failed(LLMError)
    }

    static let shared = ModelCatalog()

    @Published private(set) var state: State = .idle

    private let fetch: () async throws -> [AIModelChoice]
    /// Counts requests, so an answer that arrives after a newer request is ignored.
    private var generation = 0
    /// Set by `show`: the list stays as given and no service is asked.
    private var isFixed = false

    init(fetch: @escaping () async throws -> [AIModelChoice] = { try await AIRouter.shared.models() }) {
        self.fetch = fetch
    }

    var choices: [AIModelChoice] {
        if case .loaded(let models) = state { return models }
        return []
    }

    /// Asks the chosen service for its models, if it may be asked.
    func refresh(for settings: AISettings) async {
        guard !isFixed else { return }
        generation += 1
        let mine = generation

        let gap = settings.setupGap
        guard settings.aiEnabled, gap != .key, gap != .address else {
            state = .idle
            return
        }

        state = .loading
        do {
            let models = try await fetch()
            guard mine == generation else { return }
            state = .loaded(models)
            adopt(models, in: settings)
        } catch is CancellationError {
            guard mine == generation else { return }
            state = .idle
        } catch {
            guard mine == generation else { return }
            state = .failed((error as? LLMError) ?? .unexpected)
        }
    }

    /// Forgets the list (AI was switched off, or another service was chosen).
    func clear() {
        guard !isFixed else { return }
        generation += 1
        state = .idle
    }

    /// For tests and pictures: show this and keep it, without asking any service.
    func show(_ state: State) {
        generation += 1
        isFixed = true
        self.state = state
    }

    /// On this Mac there is no default model, so the first one found is used until the
    /// user picks another, and a model that has been removed from Ollama is replaced.
    private func adopt(_ models: [AIModelChoice], in settings: AISettings) {
        guard settings.provider == .local, let first = models.first else { return }
        let ids = Set(models.map(\.id))
        if !ids.contains(settings.talkModel) {
            settings.talkModel = first.id
        }
        if !ids.contains(settings.digestModel) {
            settings.digestModel = first.id
        }
    }
}
