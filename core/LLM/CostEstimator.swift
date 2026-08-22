import Foundation

// MARK: - CostEstimate

public struct CostEstimate: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let estimatedCostUSD: Double

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int, estimatedCostUSD: Double) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

public enum CostEstimator {
    // MARK: - Token estimation

    /// Rough token estimate: chars / 4 (standard LLM approximation).
    public static func tokenEstimate(chars: Int) -> Int {
        chars / 4
    }

    // MARK: - Cost estimation

    /// Estimate total tokens and cost for N jobs with a given resume size.
    /// Mirrors GET /api/llm-cost logic from server/api.js.
    ///
    /// Per-job cost:
    ///   - Extraction input = promptOverhead.extractChars + jobDescriptionChars
    ///   - Extraction output ≈ 1000 chars (estimated JSON response)
    ///   - Fit input = promptOverhead.fitChars + resumeCharCount + extractedJSONChars (≈ 1000)
    ///   - Fit output ≈ 800 chars (estimated JSON response)
    public static func estimateCost(
        jobCount: Int,
        resumeCharCount: Int,
        priceInputPer1M: Double,
        priceOutputPer1M: Double,
        settings _: SettingsStore
    ) -> CostEstimate {
        let overhead = PromptBuilder.promptOverheadChars()

        // Estimated chars for a typical job description (truncated at maxDescriptionChars but usually shorter)
        let typicalDescChars = min(LLMConstants.maxDescriptionChars, 8000)
        // Estimated extraction response JSON
        let extractionResponseChars = 1000
        // Estimated extracted JSON reused in fit prompt context
        let extractedJSONChars = 1000
        // Estimated fit response JSON
        let fitResponseChars = 800

        let extractInputChars = overhead.extractChars + typicalDescChars
        let fitInputChars = overhead.fitChars + resumeCharCount + extractedJSONChars

        let perJobInputChars = extractInputChars + fitInputChars
        let perJobOutputChars = extractionResponseChars + fitResponseChars

        let totalInputChars = perJobInputChars * jobCount
        let totalOutputChars = perJobOutputChars * jobCount

        let inputTokens = tokenEstimate(chars: totalInputChars)
        let outputTokens = tokenEstimate(chars: totalOutputChars)
        let totalTokens = inputTokens + outputTokens

        let inputCost = Double(inputTokens) * priceInputPer1M / 1_000_000
        let outputCost = Double(outputTokens) * priceOutputPer1M / 1_000_000
        let estimatedCostUSD = inputCost + outputCost

        return CostEstimate(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            estimatedCostUSD: estimatedCostUSD
        )
    }
}
