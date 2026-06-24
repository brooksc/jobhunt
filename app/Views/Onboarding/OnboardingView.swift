import JobhuntCore
import PDFKit
import SwiftData
import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    let onboardingManager: OnboardingManager
    let settings: SettingsStore
    let modelContainer: ModelContainer
    let resumeService: ResumeService

    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch onboardingManager.currentStep {
                case 0: WelcomeStep(
                        settings: settings,
                        modelContainer: modelContainer,
                        onboardingManager: onboardingManager
                    )
                case 1: ChromeExtensionStep()
                case 2: AIProviderStep(settings: settings)
                case 3: LocationStep(settings: settings)
                case 4: ResumeStep(resumeService: resumeService)
                case 5: FinishStep(settings: settings, onboardingManager: onboardingManager)
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom navigation
            HStack {
                // Back button
                if onboardingManager.currentStep > 0 && onboardingManager.currentStep < totalSteps - 1 {
                    Button("Back") {
                        onboardingManager.currentStep -= 1
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else {
                    Spacer().frame(width: 60)
                }

                Spacer()

                // Step dots
                HStack(spacing: 6) {
                    ForEach(0 ..< totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == onboardingManager.currentStep ? Color.accentColor : Color.secondary
                                .opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                // Skip / Continue (not shown on welcome or finish steps)
                if onboardingManager.currentStep > 0 && onboardingManager.currentStep < totalSteps - 1 {
                    HStack(spacing: 12) {
                        Button("Skip") {
                            onboardingManager.currentStep += 1
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Button("Continue") {
                            onboardingManager.currentStep += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    Spacer().frame(width: 120)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    let settings: SettingsStore
    let modelContainer: ModelContainer
    let onboardingManager: OnboardingManager

    @State private var isSeeding = false
    @State private var seedError: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "briefcase.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Welcome to JobHunt")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Track job applications, score fit with AI, and stay on top of your search.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Get Started") {
                    onboardingManager.currentStep = 1
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    Task { await seedDemo() }
                } label: {
                    if isSeeding {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Loading demo…")
                        }
                    } else {
                        Text("Try Demo Mode")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSeeding)

                if let error = seedError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .padding(32)
    }

    private func seedDemo() async {
        isSeeding = true
        seedError = nil
        do {
            let store = BackgroundStore(modelContainer: modelContainer)
            try await DemoSeeder.seedDemo(into: store)
            onboardingManager.complete(settings: settings)
        } catch {
            seedError = "Demo setup failed: \(error.localizedDescription)"
        }
        isSeeding = false
    }
}

// MARK: - Step 2: Chrome Extension

private struct ChromeExtensionStep: View {
    private let storeURL = "https://chromewebstore.google.com/detail/jobhunt-capture/jekcbebhfeidkpapienoflbcaeeknlch"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Install the Chrome Extension")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("The JobHunt extension lets you capture job postings with one click from any website.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(spacing: 12) {
                if let url = URL(string: storeURL) {
                    Link(destination: url) {
                        Label("Open Chrome Web Store", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            Divider()
                .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 6) {
                Text("Manual install (developer mode):")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("1. Open chrome://extensions in Chrome")
                Text("2. Enable \"Developer mode\" (top right)")
                Text("3. Click \"Load unpacked\" and select the extension folder")
            }
            .font(.callout)
            .frame(maxWidth: 400, alignment: .leading)

            Spacer()
        }
        .padding(32)
    }
}

// MARK: - Step 3: AI Provider

private struct AIProviderStep: View {
    let settings: SettingsStore
    @State private var model: AIProviderFormModel

    init(settings: SettingsStore) {
        self.settings = settings
        _model = State(initialValue: AIProviderFormModel(settings: settings))
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Configure AI Provider")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Picker("Provider", selection: Binding(
                    get: { model.selectedProviderID },
                    set: { model.handleProviderChange(to: $0) }
                )) {
                    ForEach(AIProviderFormModel.ProviderOption.all) { opt in
                        Text(opt.label).tag(opt.id)
                    }
                }

                if model.selectedProviderID == "lmstudio" || model.selectedProviderID == "custom" {
                    TextField("Base URL", text: Binding(
                        get: { model.baseURLText },
                        set: { model.onBaseURLChanged($0) }
                    ))
                }
                if model.selectedProviderID == "lmstudio", let url = URL(string: "https://lmstudio.ai/download") {
                    Link("Download LM Studio", destination: url).font(.caption)
                }

                if model.needsAPIKey {
                    SecureField("API Key", text: Binding(
                        get: { model.apiKeyText },
                        set: { model.onAPIKeyChanged($0) }
                    ))
                    // TASK-464: per-provider "Get API key" link.
                    if let urlString = AIProviderFormModel.ProviderOption.find(model.selectedProviderID).apiKeyURL,
                       let keyURL = URL(string: urlString) {
                        Link("Get an API key →", destination: keyURL).font(.caption)
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
                            if !model.fetchedModels.contains(model.modelText) {
                                Text("Select a model…").tag("")
                            }
                            ForEach(model.fetchedModels, id: \.self) { Text($0).tag($0) }
                        }
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
            }
            .formStyle(.grouped)
            .frame(maxHeight: 260)
        }
        .padding(24)
        .onAppear { model.syncFromSettings() }
        .sheet(item: Binding(get: { model.pendingConsent }, set: { model.pendingConsent = $0 })) { request in
            let opt = AIProviderFormModel.ProviderOption.find(request.id)
            LLMConsentSheet(
                providerName: opt.label,
                providerID: request.id,
                privacyURL: opt.privacyURL,
                settings: settings,
                // .sheet(item:) auto-clears pendingConsent on dismiss.
                onAgree: { model.applyProviderChange(to: request.id) },
                onCancel: {}
            )
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch model.connectionStatus {
        case .idle, .testing: EmptyView()
        case let .success(msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        case let .failure(msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.callout).lineLimit(2)
        }
    }
}

// MARK: - Step 4: Location Preferences

private struct LocationStep: View {
    let settings: SettingsStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Location Preferences")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
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
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 280)
        }
        .padding(24)
    }
}

// MARK: - Step 5: Resume

private struct ResumeStep: View {
    let resumeService: ResumeService

    @State private var resumeText: String = ""
    @State private var resumeName: String = ""
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Import Your Resume")
                .font(.title2)
                .fontWeight(.semibold)

            Text("JobHunt uses your resume to score how well each job fits your background.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if resumeText.isEmpty {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Import Resume (.txt or .pdf)", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isImporting)

                if let error = importError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("You can skip this and add a resume later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(resumeName, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .fontWeight(.medium)

                        Spacer()

                        Button("Change") {
                            resumeText = ""
                            resumeName = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    }

                    ScrollView {
                        Text(resumeText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxWidth: 400)
            }

            Spacer()
        }
        .padding(24)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.plainText, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Permission denied to read file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let filename = url.lastPathComponent
            let text: String

            if url.pathExtension.lowercased() == "pdf" {
                guard let doc = PDFDocument(url: url) else {
                    importError = "Could not read PDF."
                    return
                }
                text = (0 ..< doc.pageCount)
                    .compactMap { doc.page(at: $0)?.string }
                    .joined(separator: "\n")
            } else {
                text = try String(contentsOf: url, encoding: .utf8)
            }

            resumeText = text
            resumeName = filename
            importError = nil

            // Persist the resume
            Task {
                await saveResume(name: filename, text: text)
            }
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func saveResume(name: String, text: String) async {
        do {
            try await resumeService.addResume(name: name, text: text)
        } catch {
            // Non-fatal: user can add resume later in settings
        }
    }
}

// MARK: - Step 6: Finish

private struct FinishStep: View {
    let settings: SettingsStore
    let onboardingManager: OnboardingManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("You're all set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Here's what's configured:")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ConfigRow(
                    icon: "cpu",
                    label: "AI Provider",
                    value: providerLabel
                )
                ConfigRow(
                    icon: "location",
                    label: "Location Filter",
                    value: settings.locationFilterEnabled ? locationSummary : "Disabled"
                )
            }
            .frame(maxWidth: 360, alignment: .leading)

            Spacer()

            Button("Start Using JobHunt") {
                onboardingManager.complete(settings: settings)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            if let helpURL = URL(string: "https://jobhunt-app.com/help/") {
                Link("Visit the help guide", destination: helpURL)
                    .font(.callout)
            }

            Spacer()
        }
        .padding(32)
    }

    private var providerLabel: String {
        let providerLabels: [String: String] = [
            "lmstudio": "LM Studio (local)",
            "openai": "OpenAI",
            "anthropic": "Anthropic",
            "google": "Google",
            "openrouter": "OpenRouter",
            "custom": "Custom"
        ]
        return providerLabels[settings.llmProvider] ?? settings.llmProvider
    }

    private var locationSummary: String {
        var types: [String] = []
        if settings.locationAllowRemote { types.append("Remote") }
        if settings.locationAllowHybrid { types.append("Hybrid") }
        if settings.locationAllowOnsite { types.append("Onsite") }
        return types.isEmpty ? "None" : types.joined(separator: ", ")
    }
}

private struct ConfigRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
        }
    }
}
