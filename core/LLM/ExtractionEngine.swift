import Foundation
import SwiftData

// MARK: - ExtractionResult

public struct ExtractionResult: Sendable {
    public let extractedJSON: String
    public let title: String?
    public let company: String?
    public let location: String?
    public let remoteType: RemoteType?
    public let salaryMin: Int?
    public let salaryMax: Int?
    public let salaryCurrency: String?
    public let salaryNote: String?
    public let employmentType: String?
    public let seniority: String?
    public let applicationURL: String?
    public let extractionConfidence: Double?
    public let extractionModel: String
    public let promptChars: Int
    public let responseChars: Int
}

// MARK: - ExtractionEngine

public enum ExtractionEngine {

    // MARK: - Extract

    /// Extract job fields from a capture via LLM.
    /// Mirrors processRequest (extract path) in server/extract.js.
    public static func extract(
        job: Job,
        provider: any LLMProvider,
        settings: SettingsStore
    ) async throws -> ExtractionResult {
        guard let capture = job.capture else {
            throw ExtractionEngineError.noCaptureText
        }

        let description = captureText(capture)
        guard !description.isEmpty else {
            throw ExtractionEngineError.noCaptureText
        }

        let url = capture.canonicalURL ?? capture.url
        let pageTitle = capture.pageTitle

        let locationContext = LocationContext(
            preferredLocations: settings.preferredLocations,
            allowRemote: settings.locationAllowRemote,
            allowHybrid: settings.locationAllowHybrid,
            allowOnsite: settings.locationAllowOnsite
        )

        let messages = PromptBuilder.buildExtractionPrompt(
            description: description,
            url: url,
            pageTitle: pageTitle,
            locationContext: locationContext
        )

        let promptText = messages.map { $0.content }.joined()
        let promptChars = promptText.count

        let request = ChatRequest(messages: messages, model: settings.llmModel)
        let response = try await provider.complete(request)
        let responseChars = response.content.count

        let repairedJSON = try repairJSON(response.content)

        guard let data = repairedJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionEngineError.invalidJSON(repairedJSON)
        }

        var extracted: [String: Any?] = raw.mapValues { $0 as Any? }

        let normalizer = JobFieldNormalizer()
        extracted = normalizer.normalize(
            extracted: extracted,
            sourceText: description,
            url: url,
            preferredLocations: settings.locationFilterEnabled ? settings.preferredLocations : nil
        )

        let confidence = computeConfidence(extracted["confidence"])

        let resultJSON = (try? JSONSerialization.data(withJSONObject: extracted.compactMapValues { $0 }))
            .flatMap { String(data: $0, encoding: .utf8) } ?? repairedJSON

        let remoteTypeStr = extracted["remote_type"] as? String
        let remoteType: RemoteType? = remoteTypeStr.flatMap { RemoteType(rawValue: $0) }

        return ExtractionResult(
            extractedJSON: resultJSON,
            title: extracted["title"] as? String,
            company: extracted["company"] as? String,
            location: extracted["location"] as? String,
            remoteType: remoteType,
            salaryMin: extracted["salary_min"] as? Int,
            salaryMax: extracted["salary_max"] as? Int,
            salaryCurrency: extracted["salary_currency"] as? String,
            salaryNote: extracted["salary_note"] as? String,
            employmentType: extracted["employment_type"] as? String,
            seniority: extracted["seniority"] as? String,
            applicationURL: extracted["application_url"] as? String,
            extractionConfidence: confidence,
            extractionModel: response.model,
            promptChars: promptChars,
            responseChars: responseChars
        )
    }

    // MARK: - Score Fit

    /// Score job fit against a single resume via LLM.
    /// Mirrors processFitScoreRequest in server/extract.js.
    public static func scoreFit(
        job: Job,
        resume: Resume,
        provider: any LLMProvider
    ) async throws -> FitScoreResult {
        guard !resume.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionEngineError.emptyResumeText
        }

        let extractedContext = buildJobContext(from: job)
        let messages = PromptBuilder.buildFitPrompt(
            extractedJob: extractedContext,
            resumeText: resume.text
        )

        let request = ChatRequest(messages: messages, model: job.extractionModel ?? "")
        let response = try await provider.complete(request)

        let repairedJSON = try repairJSON(response.content)
        guard let data = repairedJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionEngineError.invalidJSON(repairedJSON)
        }

        let dimensions = parseDimensions(raw["dimensions"])
        let requirementsNotMet = (raw["requirements_not_met"] as? [Any])?
            .compactMap { $0 as? String } ?? []

        return FitScorer.computeScore(
            dimensions: dimensions,
            requirementsNotMet: requirementsNotMet
        )
    }

    // MARK: - Private helpers

    private static func captureText(_ capture: Capture) -> String {
        capture.cleanedDescription ?? capture.visibleText ?? capture.selectedText ?? ""
    }

    private static func computeConfidence(_ raw: Any??) -> Double? {
        guard let outer = raw, let inner = outer else { return nil }
        if let dict = inner as? [String: Any] {
            let values = dict.values.compactMap { val -> Double? in
                if let d = val as? Double { return d }
                if let i = val as? Int { return Double(i) }
                return nil
            }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        return nil
    }

    private static func buildJobContext(from job: Job) -> ExtractedJobContext {
        var title = job.title
        var company = job.company
        var seniority = job.seniority
        var summary: String?
        var requirements: [String] = []
        var niceToHaves: [String] = []
        var skills: [String] = []
        var applicationInstructions: String?

        if let jsonStr = job.extractedJSON,
           let data = jsonStr.data(using: .utf8),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = title ?? raw["title"] as? String
            company = company ?? raw["company"] as? String
            seniority = seniority ?? raw["seniority"] as? String
            summary = raw["summary"] as? String
            requirements = (raw["requirements"] as? [Any])?.compactMap { $0 as? String } ?? []
            niceToHaves = (raw["nice_to_haves"] as? [Any])?.compactMap { $0 as? String } ?? []
            skills = (raw["skills"] as? [Any])?.compactMap { $0 as? String } ?? []
            applicationInstructions = raw["application_instructions"] as? String
        }

        return ExtractedJobContext(
            title: title,
            company: company,
            seniority: seniority,
            summary: summary,
            requirements: requirements,
            niceToHaves: niceToHaves,
            skills: skills,
            applicationInstructions: applicationInstructions
        )
    }

    private static func parseDimensions(_ raw: Any?) -> [String: Double] {
        guard let arr = raw as? [[String: Any]] else { return [:] }
        var result: [String: Double] = [:]
        for item in arr {
            guard let name = item["name"] as? String else { continue }
            if let score = item["score"] as? Double {
                result[name] = min(100, max(0, score.rounded()))
            } else if let score = item["score"] as? Int {
                result[name] = min(100, max(0, Double(score)))
            }
        }
        return result
    }
}

// MARK: - ExtractionEngineError

public enum ExtractionEngineError: Error, LocalizedError {
    case noCaptureText
    case emptyResumeText
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .noCaptureText:
            return "Job has no capture text to extract from"
        case .emptyResumeText:
            return "Resume has no text to score against"
        case .invalidJSON(let json):
            return "LLM response could not be parsed as JSON: \(json.prefix(200))"
        }
    }
}
