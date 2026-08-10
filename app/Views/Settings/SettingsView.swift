import AppKit
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
        .onAppear {
            DispatchQueue.main.async {
                NSApp.windows
                    .first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" })?
                    .makeKeyAndOrderFront(nil)
            }
        }
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
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            JobsSettingsTab(settings: settings)
                .tabItem { Label("Jobs", systemImage: "briefcase") }
                .tag(1)

            LLMTab(settings: settings)
                .tabItem { Label("AI", systemImage: "cpu") }
                .tag(2)

            DataSettingsTab()
                .tabItem { Label("Data", systemImage: "externaldrive") }
                .tag(3)

            if !settings.bool(forKey: SettingsKey.hideDebugTab) {
                DebugTab()
                    .tabItem { Label("Debug", systemImage: "ant") }
                    .tag(4)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 560)
        .navigationTitle("Settings")
    }
}

// MARK: - LLMTab

struct LLMTab: View {
    let settings: SettingsStore
    @State private var model: AIProviderFormModel

    @Query(sort: \Resume.sortOrder) private var resumes: [Resume]
    @Query private var jobs: [Job]

    /// TASK-665: narrows a several-hundred-entry model menu. The picker ignores keystrokes, so
    /// without this the only way to reach a model is scrolling — slow with a mouse, impossible with
    /// a keyboard alone.
    @State private var modelFilter: String = ""
    @State private var priceInput: String = ""
    @State private var priceOutput: String = ""
    @FocusState private var inputPriceFocused: Bool
    @FocusState private var outputPriceFocused: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        _model = State(initialValue: AIProviderFormModel(settings: settings))
    }

    private var activeResume: Resume? {
        resumes.first { $0.active }
    }

    /// The models the picker shows. Always includes the current selection even when it doesn't match
    /// the filter, or typing would silently blank out what's already selected.
    private var visibleModels: [String] {
        var models = ModelFilter.matching(modelFilter, in: model.fetchedModels)
        if !model.modelText.isEmpty, !models.contains(model.modelText),
           model.fetchedModels.contains(model.modelText) {
            models.insert(model.modelText, at: 0)
        }
        return models
    }

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
            model.syncFromSettings()
            priceInput = String(settings.double(forKey: SettingsKey.llmPriceInput))
            priceOutput = String(settings.double(forKey: SettingsKey.llmPriceOutput))
        }
        .sheet(item: Binding(get: { model.pendingConsent }, set: { model.pendingConsent = $0 })) { request in
            let opt = AIProviderFormModel.ProviderOption.find(request.id)
            LLMConsentSheet(
                providerName: opt.label,
                providerID: request.id,
                privacyURL: opt.privacyURL,
                settings: settings,
                // .sheet(item:) auto-clears pendingConsent on dismiss; on cancel the Picker stays on the
                // prior provider (selectedProviderID is unchanged until consent is granted).
                onAgree: { model.applyProviderChange(to: request.id) },
                onCancel: {}
            )
        }
    }

    // MARK: - Provider section

    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: Binding(
                get: { model.selectedProviderID },
                set: { model.handleProviderChange(to: $0) }
            )) {
                ForEach(AIProviderFormModel.ProviderOption.all) { option in
                    Text(option.label).tag(option.id)
                }
            }

            if model.selectedProviderID == "lmstudio" || model.selectedProviderID == "custom" {
                TextField("Base URL", text: Binding(
                    get: { model.baseURLText },
                    set: { model.onBaseURLChanged($0) }
                ))
            }

            if model.needsAPIKey {
                SecureField("API Key", text: Binding(
                    get: { model.apiKeyText },
                    set: { model.onAPIKeyChanged($0) }
                ))
                // Re-key the field when a pasted key had whitespace stripped so AppKit re-reads the
                // sanitized value instead of leaving a stray newline glyph in its field editor (TASK-599).
                .id(model.apiKeySanitizeCount)
                if let err = settings.keychainWriteError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if ModelFilter.shouldOfferFilter(modelCount: model.fetchedModels.count) {
                HStack {
                    Text("Filter")
                    TextField("e.g. haiku, deepseek", text: $modelFilter)
                    if !modelFilter.isEmpty {
                        Text("\(visibleModels.count) of \(model.fetchedModels.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                if model.fetchedModels.isEmpty {
                    TextField("Model", text: Binding(
                        get: { model.modelText },
                        set: { model.onModelChanged($0) }
                    ))
                } else {
                    Picker("Model", selection: Binding(
                        get: { model.modelText },
                        set: { new in if !new.isEmpty { model.onModelChanged(new) } }
                    )) {
                        // No silent default — the user must pick. The placeholder represents
                        // "not yet selected" (empty model id).
                        if !visibleModels.contains(model.modelText) {
                            Text("Select a model…").tag("")
                        }
                        ForEach(visibleModels, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Clear") { model.fetchedModels = [] }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }

                if model.canFetchModels {
                    Button {
                        Task { await model.fetchModels() }
                    } label: {
                        if model.isFetchingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Fetch Models")
                        }
                    }
                    .disabled(model.isFetchingModels)
                }
            }

            if let fetchError = model.fetchError {
                Label(fetchError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if model.modelText.isEmpty {
                Text("Fetch models and choose one — no model is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // TASK-663: same recommendation as onboarding, from the same constant, next to the rows
            // it's a recommendation about.
            HStack(spacing: 8) {
                if model.selectedProviderID != ModelRecommendation.providerID
                    || model.modelText != ModelRecommendation.modelID {
                    Button("Use recommended") { model.applyRecommendation() }
                        .buttonStyle(.link)
                }
                if let url = URL(string: ModelRecommendation.helpURL) {
                    Link(ModelRecommendation.linkText, destination: url)
                }
            }
            .font(.caption)

            // TASK-462: OpenRouter free-model rotation + failover.
            if model.selectedProviderID == "openrouter" {
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
                    Task { await model.testConnection() }
                } label: {
                    if model.connectionStatus == .testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Test Connection", systemImage: "network")
                    }
                }
                .disabled(model.connectionStatus == .testing)

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
            priceError(priceInput)
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
            priceError(priceOutput)
        }
    }

    /// TASK-502 #3: an unparseable price used to be dropped in silence — the field kept the typed
    /// text and the estimate kept the old number, which is indistinguishable from a save.
    @ViewBuilder
    private func priceError(_ text: String) -> some View {
        if let message = PriceInput.validationMessage(text) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
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
                // TASK-502 #2: the number is an average over assumed description lengths, and reads
                // as a bill without saying so.
                Text(
                    "An average, not a bill. It assumes a typical job description length and the "
                        + "prices entered above — your actual cost depends on the model, how long "
                        + "each posting is, your resume, and any retries. Check your provider's "
                        + "dashboard for what you were really charged."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var connectionStatusView: some View {
        switch model.connectionStatus {
        case .idle, .testing:
            EmptyView()
        case let .success(msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
                .accessibilityLabel(msg)
                .accessibilityIdentifier("llm.connection.success")
        case let .failure(msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.callout)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .accessibilityLabel(msg)
                .accessibilityIdentifier("llm.connection.failure")
        }
    }

    /// Saves only what parses. An invalid entry leaves the stored price alone and keeps the typed
    /// text on screen under its error, so the user can fix the typo rather than retype the number.
    private func savePrices() {
        if case let .success(value) = PriceInput.parse(priceInput), let value {
            settings.setDouble(value, forKey: SettingsKey.llmPriceInput)
        }
        if case let .success(value) = PriceInput.parse(priceOutput), let value {
            settings.setDouble(value, forKey: SettingsKey.llmPriceOutput)
        }
    }
}
