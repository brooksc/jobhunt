import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(AppServices.self) private var appServices

    var body: some View {
        SettingsTabView(settings: appServices.settings)
    }
}

// MARK: - SettingsTabView

private struct SettingsTabView: View {
    let settings: SettingsStore

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
        TabView {
            SettingsTab(settings: settings)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(0)

            LLMTab(settings: settings)
                .tabItem { Label("LLM", systemImage: "cpu") }
                .tag(1)

            ResumesTab(settings: settings)
                .tabItem { Label("Resumes", systemImage: "doc.text") }
                .tag(2)

            DebugTab()
                .tabItem { Label("Debug", systemImage: "ant") }
                .tag(3)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 400)
        .navigationTitle("Settings")
    }
}

// MARK: - Provider model (used by LLMTab)

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

    @State private var pendingProviderID: String?
    @State private var showingConsentSheet = false
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
        .sheet(isPresented: $showingConsentSheet, onDismiss: { pendingProviderID = nil }) {
            if let providerID = pendingProviderID {
                let provider = ProviderOption.find(providerID)
                LLMConsentSheet(
                    providerName: provider.label,
                    providerID: providerID,
                    privacyURL: provider.privacyURL,
                    settings: settings,
                    onAgree: {
                        applyProviderChange(to: providerID)
                        pendingProviderID = nil
                    },
                    onCancel: { pendingProviderID = nil }
                )
            }
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
                            pendingProviderID = "custom"
                            showingConsentSheet = true
                        }
                    }
            }

            if needsAPIKey {
                SecureField("API Key", text: $apiKeyText)
                    .onSubmit { saveAPIKey() }
                    .onChange(of: apiKeyText) { _, _ in saveAPIKey() }
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
        case let .failure(msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.callout).lineLimit(2)
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
            pendingProviderID = newID
            showingConsentSheet = true
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
                apiKey: apiKeyText
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
