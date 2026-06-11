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
        ProviderOption(id: "custom", label: "Custom", isCloud: false, privacyURL: nil),
        ProviderOption(id: "foundation_models", label: "Apple Intelligence", isCloud: false, privacyURL: nil)
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
            diagnosticsSection
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
                        selectedProviderID = providerID
                        settings.llmProvider = providerID
                        syncAPIKey()
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

            if selectedProviderID == "foundation_models" {
                if #available(macOS 26, *) {
                    Text("Apple Intelligence — no additional configuration required.")
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "Apple Intelligence requires macOS 26 or later.",
                        systemImage: "exclamationmark.triangle"
                    )
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

            if selectedProviderID != "foundation_models" {
                HStack {
                    if fetchedModels.isEmpty {
                        TextField("Model", text: $modelText)
                            .onSubmit { settings.llmModel = modelText }
                            .onChange(of: modelText) { _, new in settings.llmModel = new }
                    } else {
                        Picker("Model", selection: $modelText) {
                            ForEach(fetchedModels, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: modelText) { _, new in settings.llmModel = new }
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

    // MARK: - Diagnostics section

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Picker("Debug logging", selection: Binding(
                get: { settings.string(forKey: SettingsKey.llmDebugLevel) },
                set: { settings.set($0, forKey: SettingsKey.llmDebugLevel) }
            )) {
                Text("Errors only").tag("errors")
                Text("Requests").tag("requests")
                Text("Full (verbose)").tag("full")
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
            let lower = baseURLText.lowercased()
            return !lower.contains("localhost") && !lower.contains("127.0.0.1") && !lower.contains("0.0.0.0")
        default:
            return false
        }
    }

    private var canFetchModels: Bool {
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

    private func syncAPIKey() {
        apiKeyText = settings.apiKey(forProvider: selectedProviderID)
    }

    private func saveAPIKey() {
        settings.setAPIKey(apiKeyText, forProvider: selectedProviderID)
    }

    private func handleProviderChange(to newID: String) {
        let provider = ProviderOption.find(newID)
        if provider.isCloud, !ConsentHelper.isConsented(provider: newID, settings: settings) {
            pendingProviderID = newID
            showingConsentSheet = true
        } else {
            selectedProviderID = newID
            settings.llmProvider = newID
            syncAPIKey()
        }
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
        isFetchingModels = true
        defer { isFetchingModels = false }
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
            if let models = resp.data, !models.isEmpty {
                fetchedModels = models.map(\.id)
                if !fetchedModels.contains(modelText) {
                    modelText = fetchedModels[0]
                    settings.llmModel = fetchedModels[0]
                }
            }
        } catch {
            // User can type model name manually
        }
    }
}
