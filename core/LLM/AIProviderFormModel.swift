import Foundation

/// Shared state + logic for the AI-provider setup form, used by BOTH the Settings AI tab and the
/// onboarding provider step so they can't drift (TASK-541). The two views differ only in layout;
/// every decision — API-key requirement, consent triggering, the no-model Test-Connection guard,
/// API-key whitespace trimming, and provider-scoped model fetches — lives here and is unit-tested.
///
/// Pure enough to live in Core (no SwiftUI), so the behaviors are testable without the OS. The model
/// fetcher is injectable so the "a slow fetch can't clobber a newer provider" rule can be tested.
@MainActor
@Observable
public final class AIProviderFormModel {
    public typealias ModelLister = @Sendable (_ provider: String, _ baseURL: String, _ apiKey: String) async throws
        -> [String]

    public enum ConnectionStatus: Equatable, Sendable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    /// Identifiable so both forms can drive an `.sheet(item:)` consent sheet (the provider id is the id).
    public struct ConsentRequest: Identifiable, Equatable, Sendable {
        public let id: String
        public init(id: String) {
            self.id = id
        }
    }

    /// Provider metadata shared by both forms (id, label, cloud flag, privacy + API-key URLs).
    public struct ProviderOption: Identifiable, Hashable, Sendable {
        public let id: String
        public let label: String
        public let isCloud: Bool
        public let privacyURL: String?
        public let apiKeyURL: String?

        public static let all: [ProviderOption] = [
            .init(id: "lmstudio", label: "LM Studio", isCloud: false, privacyURL: nil, apiKeyURL: nil),
            .init(
                id: "openai", label: "OpenAI", isCloud: true,
                privacyURL: "https://openai.com/policies/privacy-policy",
                apiKeyURL: "https://platform.openai.com/api-keys"
            ),
            .init(
                id: "anthropic", label: "Anthropic", isCloud: true,
                privacyURL: "https://www.anthropic.com/privacy",
                apiKeyURL: "https://console.anthropic.com/settings/keys"
            ),
            .init(
                id: "google", label: "Google", isCloud: true,
                privacyURL: "https://policies.google.com/privacy",
                apiKeyURL: "https://aistudio.google.com/app/apikey"
            ),
            .init(
                id: "openrouter", label: "OpenRouter", isCloud: true,
                privacyURL: "https://openrouter.ai/privacy",
                apiKeyURL: "https://openrouter.ai/keys"
            ),
            .init(id: "custom", label: "Custom", isCloud: false, privacyURL: nil, apiKeyURL: nil)
        ]

        public static func find(_ id: String) -> ProviderOption {
            all.first { $0.id == id } ?? all[0]
        }
    }

    public let settings: SettingsStore
    private let listModels: ModelLister

    public var selectedProviderID: String
    public var apiKeyText: String = ""
    /// Bumped whenever `onAPIKeyChanged` actually had to strip characters (e.g. a pasted key with a
    /// trailing newline). The view keys the secure field's `.id()` on this so AppKit re-reads the
    /// sanitized value — its field editor otherwise keeps showing the pasted whitespace glyph even
    /// though the stored key is already clean (TASK-599).
    public private(set) var apiKeySanitizeCount = 0
    public var baseURLText: String = ""
    public var modelText: String = ""
    public var fetchedModels: [String] = []
    public var isFetchingModels = false
    public var fetchError: String?
    public var connectionStatus: ConnectionStatus = .idle
    /// Non-nil when a provider/URL change needs consent before it's applied. The view presents a sheet
    /// keyed off this; `applyProviderChange(to:)` is the on-agree action.
    public var pendingConsent: ConsentRequest?

    public init(
        settings: SettingsStore,
        listModels: @escaping ModelLister = { try await ModelCatalog.listModels(provider: $0, baseURL: $1, apiKey: $2) }
    ) {
        self.settings = settings
        self.listModels = listModels
        selectedProviderID = settings.llmProvider
    }

    // MARK: - Derived rules

    /// Whether this provider needs an API key. A custom **loopback** endpoint (LM Studio-style) needs
    /// none; a custom **remote** endpoint does. (Onboarding used to require a key for every custom URL.)
    public var needsAPIKey: Bool {
        // Shared base-URL-aware policy with the readiness gate so the form and queue agree (TASK-568).
        LLMProviderFactory.requiresAPIKey(provider: selectedProviderID, baseURL: baseURLText)
    }

    public var canFetchModels: Bool {
        switch selectedProviderID {
        case "openai", "anthropic", "google": !apiKeyText.isEmpty
        case "openrouter": true // public model list — no key required
        case "lmstudio", "custom": !baseURLText.isEmpty
        default: false
        }
    }

    // MARK: - Sync with settings

    public func syncFromSettings() {
        selectedProviderID = settings.llmProvider
        modelText = settings.modelForProvider(settings.llmProvider)
        baseURLText = settings.llmBaseURL
        syncAPIKey()
        fetchedModels = []
        fetchError = nil
        if canFetchModels { Task { await fetchModels() } }
    }

    public func syncAPIKey() {
        apiKeyText = settings.apiKey(forProvider: selectedProviderID)
    }

    // MARK: - Field edits

    /// Persist the base URL. A custom **remote** URL that isn't yet consented triggers the consent
    /// sheet (matching Settings) — onboarding previously skipped consent for remote custom endpoints.
    public func onBaseURLChanged(_ new: String) {
        baseURLText = new
        settings.llmBaseURL = new
        if selectedProviderID == "custom",
           !ConsentHelper.isConsented(provider: "custom", settings: settings) {
            pendingConsent = ConsentRequest(id: "custom")
        }
    }

    /// Strip whitespace from the API key the instant it's typed — a pasted trailing newline silently
    /// breaks auth (e.g. Google 401). The cleaned value is stored and persisted.
    public func onAPIKeyChanged(_ new: String) {
        let cleaned = new.filter { !$0.isWhitespace }
        // Only bump when stripping actually changed the string, so ordinary typing doesn't force the
        // field to rebuild (and drop focus) — a pasted newline/space does, and the field re-syncs.
        if cleaned != new { apiKeySanitizeCount += 1 }
        apiKeyText = cleaned
        // The throw exists for programmatic callers (restore, key rotation). This is the interactive
        // path and can't propagate: `setAPIKey` has already set `keychainWriteError`, which
        // SettingsView renders, so the user still sees a failed write. Explicitly discarded, not
        // accidentally.
        try? settings.setAPIKey(cleaned, forProvider: selectedProviderID)
    }

    public func onModelChanged(_ new: String) {
        modelText = new
        settings.setModelForProvider(new, provider: selectedProviderID)
    }

    // MARK: - Provider change (consent-gated)

    public func handleProviderChange(to newID: String) {
        if !ConsentHelper.isConsented(provider: newID, settings: settings) {
            pendingConsent = ConsentRequest(id: newID)
        } else {
            applyProviderChange(to: newID)
        }
    }

    /// Activate a provider: clear the model so the user must explicitly pick one for the new provider,
    /// re-sync the key, and auto-fetch the model list when possible.
    public func applyProviderChange(to newID: String) {
        selectedProviderID = newID
        settings.llmProvider = newID
        modelText = settings.modelForProvider(newID)
        settings.llmModel = modelText
        syncAPIKey()
        fetchedModels = []
        fetchError = nil
        if canFetchModels { Task { await fetchModels() } }
    }

    // MARK: - Model fetch (provider-scoped)

    public func fetchModels() async {
        // Capture the provider this fetch is for, so a slow fetch that resolves after the user
        // switched providers can't clobber the now-current provider's list (TASK-468/541).
        let provider = selectedProviderID
        isFetchingModels = true
        fetchError = nil
        defer { isFetchingModels = false }
        do {
            let models = try await listModels(
                provider,
                baseURLText.isEmpty ? settings.llmBaseURL : baseURLText,
                apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard provider == selectedProviderID else { return }
            fetchedModels = models
            if models.isEmpty {
                fetchError = "No models returned by the provider"
            } else if !models.contains(modelText) {
                modelText = ""
                settings.setModelForProvider("", provider: provider)
            }
        } catch {
            guard provider == selectedProviderID else { return }
            fetchedModels = []
            fetchError = error.localizedDescription
        }
    }

    // MARK: - Test connection (no-model guard)

    public func testConnection() async {
        // A request with no model hits e.g. Google's `models/:generateContent` and returns a baffling
        // 404. Fail fast with a clear instruction instead (onboarding previously sent an empty model).
        let model = settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            connectionStatus = .failure("Select or enter a model first (use Fetch Models, or type a model name).")
            return
        }
        connectionStatus = .testing
        let provider = LLMProviderFactory.makeProvider(settings: settings)
        let request = ChatRequest(
            messages: [ChatMessage(role: "user", content: "Reply with the word OK and nothing else.")],
            model: model,
            maxTokens: 16
        )
        do {
            let response = try await provider.complete(request)
            let preview = String(response.content.prefix(40))
            connectionStatus = .success(preview.isEmpty ? "Connected" : preview)
        } catch let LLMProviderError.httpError(code, body) {
            connectionStatus = .failure(Self.httpFailureMessage(code: code, body: body))
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }

    /// Turn a provider HTTP error into something actionable: a 401/403 hint plus the provider's own
    /// error message (Google/OpenAI/Anthropic return `{ "error": { "message": … } }`).
    public static func httpFailureMessage(code: Int, body: String) -> String {
        var text = "HTTP \(code)"
        if code == 401 || code == 403 {
            text += " — the API key was rejected. Use an unrestricted key (no HTTP-referrer / IP / app "
                + "restrictions) with the provider's API enabled."
        }
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = obj["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            text += "\n\(message)"
        }
        return text
    }
}
