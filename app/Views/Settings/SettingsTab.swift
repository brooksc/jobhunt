import JobhuntCore
import SwiftUI

// MARK: - Provider model

private struct ProviderOption: Identifiable, Hashable {
    let id: String
    let label: String
    let isCloud: Bool
    let privacyURL: String?

    static let all: [ProviderOption] = [
        ProviderOption(id: "lmstudio", label: "LM Studio", isCloud: false, privacyURL: nil),
        ProviderOption(
            id: "openai",
            label: "OpenAI",
            isCloud: true,
            privacyURL: "https://openai.com/policies/privacy-policy"
        ),
        ProviderOption(
            id: "anthropic",
            label: "Anthropic",
            isCloud: true,
            privacyURL: "https://www.anthropic.com/privacy"
        ),
        ProviderOption(id: "google", label: "Google", isCloud: true, privacyURL: "https://policies.google.com/privacy"),
        ProviderOption(
            id: "openrouter",
            label: "OpenRouter",
            isCloud: true,
            privacyURL: "https://openrouter.ai/privacy"
        ),
        ProviderOption(id: "custom", label: "Custom", isCloud: false, privacyURL: nil),
        ProviderOption(id: "apple", label: "Apple Intelligence", isCloud: false, privacyURL: nil)
    ]

    static func find(_ id: String) -> ProviderOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - SettingsTab

struct SettingsTab: View {
    let settings: SettingsStore

    @State private var pendingProviderID: String?
    @State private var showingConsentSheet = false

    /// Local mirror for the provider picker (to allow reverting on Cancel)
    @State private var selectedProviderID: String = "lmstudio"

    /// API key fields (not persisted until edited)
    @State private var apiKeyText: String = ""

    // Connection test
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isFetchingModels = false

    // Model / URL
    @State private var modelText: String = ""
    @State private var baseURLText: String = ""

    private enum ConnectionStatus {
        case idle, testing, success(String), failure(String)
    }

    private var selectedProvider: ProviderOption {
        ProviderOption.find(selectedProviderID)
    }

    // MARK: - Body

    var body: some View {
        Form {
            providerSection
            locationSection
            intervalsSection
        }
        .formStyle(.grouped)
        .onAppear { syncFromSettings() }
        .sheet(isPresented: $showingConsentSheet) {
            if let providerID = pendingProviderID {
                let provider = ProviderOption.find(providerID)
                LLMConsentSheet(
                    providerName: provider.label,
                    providerID: providerID,
                    privacyURL: provider.privacyURL,
                    settings: settings,
                    onAgree: {
                        selectedProviderID = providerID
                        settings.llmProvider = providerID
                        syncAPIKey()
                        pendingProviderID = nil
                    },
                    onCancel: {
                        // Revert — keep old selection
                        pendingProviderID = nil
                    }
                )
            }
        }
    }

    // MARK: - Provider section

    private var providerSection: some View {
        Section("LLM Provider") {
            Picker("Provider", selection: Binding(
                get: { selectedProviderID },
                set: { newID in handleProviderChange(to: newID) }
            )) {
                ForEach(ProviderOption.all) { option in
                    Text(option.label).tag(option.id)
                }
            }

            if selectedProviderID == "apple" {
                if #available(macOS 26, *) {
                    Text("Apple Intelligence — no additional configuration required.")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Apple Intelligence requires macOS 26 or later.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            if selectedProviderID == "lmstudio" || selectedProviderID == "custom" {
                TextField("Base URL", text: $baseURLText)
                    .onSubmit { settings.llmBaseURL = baseURLText }
                    .onChange(of: baseURLText) { _, new in settings.llmBaseURL = new }
            }

            if needsAPIKey {
                SecureField("API Key", text: $apiKeyText)
                    .onSubmit { saveAPIKey() }
                    .onChange(of: apiKeyText) { _, _ in saveAPIKey() }
            }

            if selectedProviderID == "openrouter" {
                Toggle("Free-tier model rotation", isOn: Binding(
                    get: { settings.bool(forKey: SettingsKey.llmOpenRouterFreeRotate) },
                    set: { settings.setBool($0, forKey: SettingsKey.llmOpenRouterFreeRotate) }
                ))
            }

            if selectedProviderID != "apple" {
                HStack {
                    TextField("Model", text: $modelText)
                        .onSubmit { settings.llmModel = modelText }
                        .onChange(of: modelText) { _, new in settings.llmModel = new }

                    if canFetchModels {
                        Button {
                            Task { await fetchModels() }
                        } label: {
                            if isFetchingModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Fetch Models")
                            }
                        }
                        .disabled(isFetchingModels)
                    }
                }
            }

            HStack {
                Button {
                    Task { await testConnection() }
                } label: {
                    if case .testing = connectionStatus {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Test Connection", systemImage: "network")
                    }
                }
                .disabled({
                    if case .testing = connectionStatus { return true }
                    return false
                }())

                Spacer()

                connectionStatusView
            }

            Stepper(
                "Timeout: \(settings.llmTimeout)s",
                value: Binding(
                    get: { settings.llmTimeout },
                    set: { settings.llmTimeout = $0 }
                ),
                in: 10 ... 600,
                step: 10
            )
        }
    }

    // MARK: - Location section

    private var locationSection: some View {
        Section("Location Filter") {
            Toggle("Enable location filter", isOn: Binding(
                get: { settings.locationFilterEnabled },
                set: { settings.locationFilterEnabled = $0 }
            ))

            if settings.locationFilterEnabled {
                Toggle("Remote", isOn: Binding(
                    get: { settings.locationAllowRemote },
                    set: { settings.locationAllowRemote = $0 }
                ))
                Toggle("Hybrid", isOn: Binding(
                    get: { settings.locationAllowHybrid },
                    set: { settings.locationAllowHybrid = $0 }
                ))
                Toggle("Onsite", isOn: Binding(
                    get: { settings.locationAllowOnsite },
                    set: { settings.locationAllowOnsite = $0 }
                ))

                TextField("Preferred locations (comma-separated cities)", text: Binding(
                    get: { settings.preferredLocations },
                    set: { settings.preferredLocations = $0 }
                ))

                TextField("Preferred metros (comma-separated)", text: Binding(
                    get: { settings.preferredMetros },
                    set: { settings.preferredMetros = $0 }
                ))
            }
        }
    }

    // MARK: - Intervals section

    private var intervalsSection: some View {
        Section("Intervals") {
            Stepper(
                "Site review interval: \(settings.siteReviewIntervalDays) days",
                value: Binding(
                    get: { settings.siteReviewIntervalDays },
                    set: { settings.siteReviewIntervalDays = $0 }
                ),
                in: 1 ... 90
            )

            Stepper(
                "Follow-up default: \(settings.followupDefaultDays) days",
                value: Binding(
                    get: { settings.followupDefaultDays },
                    set: { settings.followupDefaultDays = $0 }
                ),
                in: 1 ... 60
            )
        }
    }

    // MARK: - Helpers

    private var needsAPIKey: Bool {
        switch selectedProviderID {
        case "openai", "anthropic", "google", "openrouter", "custom": true
        default: false
        }
    }

    private var canFetchModels: Bool {
        // Only show Fetch Models for providers where we can hit an API
        switch selectedProviderID {
        case "openrouter": !apiKeyText.isEmpty
        case "lmstudio", "custom": !baseURLText.isEmpty
        default: false
        }
    }

    private func syncFromSettings() {
        selectedProviderID = settings.llmProvider
        modelText = settings.llmModel
        baseURLText = settings.llmBaseURL
        syncAPIKey()
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .idle, .testing:
            EmptyView()
        case let .success(msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case let .failure(msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(2)
        }
    }

    private func syncAPIKey() {
        apiKeyText = settings.apiKey(forProvider: selectedProviderID)
    }

    private func saveAPIKey() {
        settings.setAPIKey(apiKeyText, forProvider: selectedProviderID)
    }

    private func handleProviderChange(to newID: String) {
        let provider = ProviderOption.find(newID)
        if provider.isCloud && !ConsentHelper.isConsented(provider: newID, settings: settings) {
            pendingProviderID = newID
            showingConsentSheet = true
        } else {
            selectedProviderID = newID
            settings.llmProvider = newID
            syncAPIKey()
        }
    }

    func testConnection() async {
        connectionStatus = .testing
        let provider = LLMProviderFactory.makeProvider(settings: settings)
        let request = ChatRequest(
            messages: [ChatMessage(role: "user", content: "Reply with the word OK and nothing else.")],
            model: settings.llmModel,
            maxTokens: 16
        )
        do {
            let response = try await provider.complete(request)
            let preview = String(response.content.prefix(40))
            connectionStatus = .success(preview.isEmpty ? "Connected" : preview)
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }

    private func fetchModels() async {
        isFetchingModels = true
        defer { isFetchingModels = false }
        // For LM Studio / Custom: fetch /v1/models
        let urlBase = baseURLText.isEmpty ? settings.llmBaseURL : baseURLText
        guard !urlBase.isEmpty, let url = URL(string: "\(urlBase)/v1/models") else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            if !apiKeyText.isEmpty {
                req.setValue("Bearer \(apiKeyText)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            // swiftlint:disable:next nesting type_name
            struct ModelsResp: Decodable { struct M: Decodable { let id: String }; let data: [M]? }
            let resp = try JSONDecoder().decode(ModelsResp.self, from: data)
            if let first = resp.data?.first {
                modelText = first.id
                settings.llmModel = first.id
            }
        } catch {
            // Silently ignore — user can type manually
        }
    }
}
