import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(Router.self) private var router

    var body: some View {
        SettingsTabView(
            settings: appServices.settings,
            selectedTab: Binding(
                get: { router.settingsTab.rawValue },
                set: { router.settingsTab = SettingsPane(rawValue: $0) ?? .general }
            )
        )
    }
}

// MARK: - SettingsTabView

private struct SettingsTabView: View {
    let settings: SettingsStore
    @Binding var selectedTab: Int

    var body: some View {
        VStack(spacing: 0) {
            // TASK-388: stored settings couldn't be read — tell the user their preferences may not
            // be the saved ones and that changes won't be persisted until a relaunch succeeds.
            if let loadError = settings.loadError {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .padding([.horizontal, .top])
            }
            tabView
        }
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            SettingsTab(settings: settings)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(0)

            LLMTab(settings: settings)
                .tabItem { Label("LLM", systemImage: "cpu") }
                .tag(1)

            DebugTab()
                .tabItem { Label("Debug", systemImage: "ant") }
                .tag(2)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 400)
        .navigationTitle("Settings")
    }
}

// MARK: - Provider model (used by LLMTab)

/// Identifiable wrapper so the consent flow can drive `.sheet(item:)` (the provider id is the id).
private struct ConsentRequest: Identifiable {
    let id: String
}

private struct ProviderOption: Identifiable, Hashable {
    let id: String
    let label: String
    let isCloud: Bool
    let privacyURL: String?

    static let all: [ProviderOption] = [
        ProviderOption(id: "lmstudio", label: "LM Studio", isCloud: false, privacyURL: nil),
        ProviderOption(
            id: "openai", label: "OpenAI", isCloud: true,
            privacyURL: "https://openai.com/policies/privacy-policy"
        ),
        ProviderOption(
            id: "anthropic", label: "Anthropic", isCloud: true,
            privacyURL: "https://www.anthropic.com/privacy"
        ),
        ProviderOption(
            id: "google", label: "Google", isCloud: true,
            privacyURL: "https://policies.google.com/privacy"
        ),
        ProviderOption(
            id: "openrouter", label: "OpenRouter", isCloud: true,
            privacyURL: "https://openrouter.ai/privacy"
        ),
        ProviderOption(id: "custom", label: "Custom", isCloud: false, privacyURL: nil)
    ]

    static func find(_ id: String) -> ProviderOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - LLMTab

struct LLMTab: View {
    let settings: SettingsStore

    @Query(sort: \Resume.sortOrder) private var resumes: [Resume]
    @Query private var jobs: [Job]

    /// The provider awaiting a consent decision. Drives the consent sheet via `.sheet(item:)`, which
    /// only presents when this is non-nil and hands the value to the content — avoiding the empty-sheet
    /// race a separate `Bool` + optional read (`if let`) caused when both were set in one update.
    @State private var pendingConsent: ConsentRequest?
    @State private var selectedProviderID: String
    @State private var apiKeyText: String = ""
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isFetchingModels = false
    @State private var fetchedModels: [String] = []
    @State private var fetchError: String?
    @State private var modelText: String = ""
    @State private var baseURLText: String = ""
    @State private var priceInput: String = ""
    @State private var priceOutput: String = ""
    @FocusState private var inputPriceFocused: Bool
    @FocusState private var outputPriceFocused: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        _selectedProviderID = State(initialValue: settings.llmProvider)
    }

    private enum ConnectionStatus {
        case idle, testing, success(String), failure(String)
    }

    private var activeResume: Resume? { resumes.first { $0.active } }

    private var costEstimate: CostEstimate? {
        let inputPrice = Double(priceInput) ?? settings.double(forKey: SettingsKey.llmPriceInput)
        let outputPrice = Double(priceOutput) ?? settings.double(forKey: SettingsKey.llmPriceOutput)
        return CostEstimator.estimateCost(
            jobCount: max(jobs.count, 1),
            resumeCharCount: activeResume?.charCount ?? 0,
            priceInputPer1M: inputPrice,
            priceOutputPer1M: outputPrice,
            settings: settings
        )
    }

    var body: some View {
        Form {
            providerSection
            pricingSection
            costSection
        }
        .formStyle(.grouped)
        .onAppear {
            syncFromSettings()
            priceInput = String(settings.double(forKey: SettingsKey.llmPriceInput))
            priceOutput = String(settings.double(forKey: SettingsKey.llmPriceOutput))
        }
        .sheet(item: $pendingConsent) { request in
            let provider = ProviderOption.find(request.id)
            LLMConsentSheet(
                providerName: provider.label,
                providerID: request.id,
                privacyURL: provider.privacyURL,
                settings: settings,
                // .sheet(item:) auto-clears pendingConsent on dismiss, so neither closure needs to.
                // On cancel the Picker stays on the prior provider (selectedProviderID is unchanged
                // until consent is granted).
                onAgree: { applyProviderChange(to: request.id) },
                onCancel: {}
            )
        }
    }

    // MARK: - Provider section

    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: Binding(
                get: { selectedProviderID },
                set: { handleProviderChange(to: $0) }
            )) {
                ForEach(ProviderOption.all) { option in
                    Text(option.label).tag(option.id)
                }
            }

            if selectedProviderID == "lmstudio" || selectedProviderID == "custom" {
                TextField("Base URL", text: $baseURLText)
                    .onSubmit { settings.llmBaseURL = baseURLText }
                    .onChange(of: baseURLText) { _, new in
                        settings.llmBaseURL = new
                        if selectedProviderID == "custom",
                           !ConsentHelper.isConsented(provider: "custom", settings: settings) {
                            pendingConsent = ConsentRequest(id: "custom")
                        }
                    }
            }

            if needsAPIKey {
                SecureField("API Key", text: $apiKeyText)
                    .onSubmit { saveAPIKey() }
                    .onChange(of: apiKeyText) { _, newValue in
                        // Strip any whitespace/newlines the moment they land in the field — an API key
                        // never contains them, and a pasted trailing newline silently breaks auth.
                        // Re-assigning fires onChange again with the cleaned value, which then saves.
                        let cleaned = newValue.filter { !$0.isWhitespace }
                        if cleaned != newValue {
                            apiKeyText = cleaned
                        } else {
                            saveAPIKey()
                        }
                    }
                if let err = settings.keychainWriteError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                if fetchedModels.isEmpty {
                    TextField("Model", text: $modelText)
                        .onSubmit { settings.setModelForProvider(modelText, provider: selectedProviderID) }
                        .onChange(of: modelText) { _, new in settings.setModelForProvider(new, provider: selectedProviderID) }
                } else {
                    Picker("Model", selection: $modelText) {
                        // No silent default — the user must pick. The placeholder represents
                        // "not yet selected" (empty model id).
                        if !fetchedModels.contains(modelText) {
                            Text("Select a model…").tag("")
                        }
                        ForEach(fetchedModels, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: modelText) { _, new in
                        guard !new.isEmpty else { return }
                        settings.setModelForProvider(new, provider: selectedProviderID)
                    }
                    Button("Clear") { fetchedModels = [] }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }

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

            if let fetchError {
                Label(fetchError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if modelText.isEmpty {
                Text("Fetch models and choose one — no model is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // TASK-462: OpenRouter free-model rotation + failover.
            if selectedProviderID == "openrouter" {
                Toggle("Rotate free structured-output models", isOn: Binding(
                    get: { settings.llmOpenRouterFreeRotate },
                    set: { settings.llmOpenRouterFreeRotate = $0 }
                ))
                Text("Round-robin over OpenRouter's free models with failover, instead of the single model above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .disabled({ if case .testing = connectionStatus { return true }; return false }())

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

    // MARK: - Pricing section

    private var pricingSection: some View {
        Section("Cost Pricing (USD per 1M tokens)") {
            HStack {
                Text("Input tokens")
                Spacer()
                TextField("0.00", text: $priceInput)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .focused($inputPriceFocused)
                    .onSubmit { savePrices() }
                    .onChange(of: inputPriceFocused) { _, focused in if !focused { savePrices() } }
            }
            HStack {
                Text("Output tokens")
                Spacer()
                TextField("0.00", text: $priceOutput)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .focused($outputPriceFocused)
                    .onSubmit { savePrices() }
                    .onChange(of: outputPriceFocused) { _, focused in if !focused { savePrices() } }
            }
        }
    }

    // MARK: - Cost estimate section

    @ViewBuilder
    private var costSection: some View {
        if let estimate = costEstimate {
            Section("Cost Estimate (\(jobs.count) jobs)") {
                LabeledContent("Input tokens") { Text(estimate.inputTokens.formatted()) }
                LabeledContent("Output tokens") { Text(estimate.outputTokens.formatted()) }
                LabeledContent("Total tokens") { Text(estimate.totalTokens.formatted()) }
                LabeledContent("Estimated cost") {
                    Text(estimate.estimatedCostUSD, format: .currency(code: "USD"))
                        .fontWeight(.semibold)
                }
                if activeResume == nil {
                    Text("Add an active resume for a more accurate estimate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }


    // MARK: - Helpers

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .idle, .testing:
            EmptyView()
        case let .success(msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
                .accessibilityIdentifier("llm.connection.success")
        case let .failure(msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.callout)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("llm.connection.failure")
        }
    }

    private var needsAPIKey: Bool {
        switch selectedProviderID {
        case "openai", "anthropic", "google", "openrouter":
            return true
        case "custom":
            return !ConsentHelper.isLoopbackURL(baseURLText)
        default:
            return false
        }
    }

    private var canFetchModels: Bool {
        switch selectedProviderID {
        case "openai", "anthropic", "google": !apiKeyText.isEmpty
        case "openrouter": true // public model list — no key required
        case "lmstudio", "custom": !baseURLText.isEmpty
        default: false
        }
    }

    private func syncFromSettings() {
        selectedProviderID = settings.llmProvider
        modelText = settings.modelForProvider(settings.llmProvider)
        baseURLText = settings.llmBaseURL
        syncAPIKey()
        fetchedModels = []
        fetchError = nil
        if canFetchModels { Task { await fetchModels() } }
    }

    private func syncAPIKey() {
        apiKeyText = settings.apiKey(forProvider: selectedProviderID)
    }

    private func saveAPIKey() {
        settings.setAPIKey(apiKeyText, forProvider: selectedProviderID)
    }

    private func handleProviderChange(to newID: String) {
        if !ConsentHelper.isConsented(provider: newID, settings: settings) {
            pendingConsent = ConsentRequest(id: newID)
        } else {
            applyProviderChange(to: newID)
        }
    }

    private func applyProviderChange(to newID: String) {
        selectedProviderID = newID
        settings.llmProvider = newID
        modelText = settings.modelForProvider(newID)
        // Keep the active model in sync with the provider's remembered choice (may be empty,
        // which forces an explicit selection before extraction can run).
        settings.llmModel = modelText
        syncAPIKey()
        fetchedModels = []
        fetchError = nil
        if canFetchModels { Task { await fetchModels() } }
    }

    private func savePrices() {
        if let v = Double(priceInput) { settings.setDouble(v, forKey: SettingsKey.llmPriceInput) }
        if let v = Double(priceOutput) { settings.setDouble(v, forKey: SettingsKey.llmPriceOutput) }
    }

    private func testConnection() async {
        // A request with no model hits e.g. Google's `models/:generateContent` and returns a baffling
        // 404. Fail fast with a clear instruction instead.
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
    /// error message (Google/OpenAI/Anthropic all return `{ "error": { "message": … } }`).
    private static func httpFailureMessage(code: Int, body: String) -> String {
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

    private func fetchModels() async {
        // TASK-468: capture the provider this fetch is for, so a slow fetch that resolves after the
        // user switched providers can't clobber the now-current provider's model list.
        let provider = selectedProviderID
        isFetchingModels = true
        fetchError = nil
        defer { isFetchingModels = false }
        do {
            let models = try await ModelCatalog.listModels(
                provider: provider,
                baseURL: baseURLText.isEmpty ? settings.llmBaseURL : baseURLText,
                apiKey: apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard provider == selectedProviderID else { return }
            fetchedModels = models
            // Do not auto-select — selection is explicit. If the remembered model is no longer in
            // the list, clear it so the picker shows the "Select a model…" placeholder.
            if models.isEmpty {
                fetchError = "No models returned by the provider"
            } else if !models.contains(modelText) {
                // Also clear the PERSISTED selection — otherwise the UI shows "unselected" while
                // settings still points at the unavailable model and extraction/testConnection use
                // it (the Picker's onChange guards !isEmpty, so it never clears it itself).
                modelText = ""
                settings.setModelForProvider("", provider: provider)
            }
        } catch {
            guard provider == selectedProviderID else { return }
            fetchedModels = []
            fetchError = error.localizedDescription
        }
    }
}
