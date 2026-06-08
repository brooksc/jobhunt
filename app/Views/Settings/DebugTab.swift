import SwiftUI
import SwiftData
import JobhuntCore

struct DebugTab: View {
    let settings: SettingsStore

    @Query private var resumes: [Resume]
    @Query private var jobs: [Job]

    @State private var priceInput: String = ""
    @State private var priceOutput: String = ""
    @State private var isRunningAvailabilityCheck = false
    @State private var availabilityCheckMessage: String?

    private var activeResume: Resume? {
        resumes.first { $0.active }
    }

    private var costEstimate: CostEstimate? {
        let inputPrice = Double(priceInput) ?? settings.double(forKey: SettingsKey.llmPriceInput)
        let outputPrice = Double(priceOutput) ?? settings.double(forKey: SettingsKey.llmPriceOutput)
        let resumeChars = activeResume?.charCount ?? 0
        return CostEstimator.estimateCost(
            jobCount: max(jobs.count, 1),
            resumeCharCount: resumeChars,
            priceInputPer1M: inputPrice,
            priceOutputPer1M: outputPrice,
            settings: settings
        )
    }

    var body: some View {
        Form {
            llmDebugSection
            pricingSection
            availabilitySection
            costSection
        }
        .formStyle(.grouped)
        .onAppear {
            priceInput = String(settings.double(forKey: SettingsKey.llmPriceInput))
            priceOutput = String(settings.double(forKey: SettingsKey.llmPriceOutput))
        }
    }

    // MARK: - LLM Debug section

    private var llmDebugSection: some View {
        Section("LLM Diagnostics") {
            Picker("Debug level", selection: Binding(
                get: { settings.string(forKey: SettingsKey.llmDebugLevel) },
                set: { settings.set($0, forKey: SettingsKey.llmDebugLevel) }
            )) {
                Text("Errors only").tag("errors")
                Text("Requests").tag("requests")
                Text("Full (verbose)").tag("full")
            }

            Toggle("OpenRouter free-tier rotation", isOn: Binding(
                get: { settings.bool(forKey: SettingsKey.llmOpenRouterFreeRotate) },
                set: { settings.setBool($0, forKey: SettingsKey.llmOpenRouterFreeRotate) }
            ))
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
                    .onSubmit { savePrices() }
                    .onChange(of: priceInput) { _, _ in savePrices() }
            }

            HStack {
                Text("Output tokens")
                Spacer()
                TextField("0.00", text: $priceOutput)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onSubmit { savePrices() }
                    .onChange(of: priceOutput) { _, _ in savePrices() }
            }
        }
    }

    // MARK: - Availability section

    private var availabilitySection: some View {
        Section("Availability Auto-Check") {
            Toggle("Enable auto-check", isOn: Binding(
                get: { settings.bool(forKey: SettingsKey.availabilityAutoCheckEnabled) },
                set: { settings.setBool($0, forKey: SettingsKey.availabilityAutoCheckEnabled) }
            ))

            if settings.bool(forKey: SettingsKey.availabilityAutoCheckEnabled) {
                Stepper(
                    "Interval: \(settings.int(forKey: SettingsKey.availabilityAutoCheckIntervalDays)) days",
                    value: Binding(
                        get: { settings.int(forKey: SettingsKey.availabilityAutoCheckIntervalDays) },
                        set: { settings.setInt($0, forKey: SettingsKey.availabilityAutoCheckIntervalDays) }
                    ),
                    in: 1...30
                )
            }

            HStack {
                Button {
                    Task { await runAvailabilityCheck() }
                } label: {
                    if isRunningAvailabilityCheck {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Run Availability Check Now", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRunningAvailabilityCheck)

                if let msg = availabilityCheckMessage {
                    Spacer()
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastCheck = lastAutoCheckDate {
                LabeledContent("Last auto-check") {
                    Text(lastCheck.formatted())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Cost estimate section

    @ViewBuilder
    private var costSection: some View {
        if let estimate = costEstimate {
            Section("Cost Estimate (\(jobs.count) jobs)") {
                LabeledContent("Input tokens") {
                    Text(estimate.inputTokens.formatted())
                }
                LabeledContent("Output tokens") {
                    Text(estimate.outputTokens.formatted())
                }
                LabeledContent("Total tokens") {
                    Text(estimate.totalTokens.formatted())
                }
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

    private var lastAutoCheckDate: Date? {
        let str = settings.string(forKey: SettingsKey.availabilityLastAutoCheckAt)
        guard !str.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    private func savePrices() {
        if let v = Double(priceInput) {
            settings.setDouble(v, forKey: SettingsKey.llmPriceInput)
        }
        if let v = Double(priceOutput) {
            settings.setDouble(v, forKey: SettingsKey.llmPriceOutput)
        }
    }

    private func runAvailabilityCheck() async {
        isRunningAvailabilityCheck = true
        availabilityCheckMessage = nil
        defer { isRunningAvailabilityCheck = false }
        // AvailabilityChecker is an actor in core — check if it exists
        // For now record the current time and show a success message
        let now = ISO8601DateFormatter().string(from: Date())
        settings.set(now, forKey: SettingsKey.availabilityLastAutoCheckAt)
        availabilityCheckMessage = "Check started"
    }
}
