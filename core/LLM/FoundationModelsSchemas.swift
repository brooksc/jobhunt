import Foundation
import FoundationModels

// Guided-generation schemas for Apple Foundation Models (macOS 26+).
//
// These @Generable types let the on-device model emit a constrained, typed structure instead of
// free-form text that must be JSON-parsed — eliminating the "Model response could not be parsed
// as valid JSON" failure class. Each type is also Encodable with snake_case CodingKeys so it
// serialises to exactly the JSON shape ExtractionEngine already consumes.

// MARK: - Job extraction

@available(macOS 26.0, *)
@Generable
struct GeneratedExtraction: Encodable {
    @Guide(description: "Company name, or null if not present") var company: String?
    @Guide(description: "Job title, or null if not present") var title: String?
    @Guide(description: "Location text as written, or null") var location: String?
    @Guide(description: "One of: remote, hybrid, onsite, unknown") var remoteType: String?
    @Guide(description: "Annual minimum salary as an integer, or null") var salaryMin: Int?
    @Guide(description: "Annual maximum salary as an integer, or null") var salaryMax: Int?
    @Guide(description: "Hourly minimum rate, or null") var salaryHourlyMin: Double?
    @Guide(description: "Hourly maximum rate, or null") var salaryHourlyMax: Double?
    @Guide(description: "Currency code/symbol, or null") var salaryCurrency: String?
    @Guide(description: "Original salary text verbatim, or null") var salaryNote: String?
    @Guide(description: "One of: full_time, part_time, contract, internship, temporary, unknown")
    var employmentType: String?
    @Guide(description: "Seniority level, or null") var seniority: String?
    @Guide(description: "Concrete skills, technologies, tools, and domains named in the posting")
    var skills: [String]
    @Guide(description: "Short neutral summary of the role, or null") var summary: String?
    @Guide(description: "Hard requirements / must-haves") var requirements: [String]
    @Guide(description: "Preferred / nice-to-have qualifications and domain signals")
    var niceToHaves: [String]
    @Guide(description: "Benefits and perks") var benefits: [String]
    @Guide(description: "Direct application URL, or null") var applicationUrl: String?
    @Guide(description: "Verbatim submission instructions, or null") var applicationInstructions: String?

    enum CodingKeys: String, CodingKey {
        case company, title, location, seniority, skills, summary, requirements, benefits
        case remoteType = "remote_type"
        case salaryMin = "salary_min"
        case salaryMax = "salary_max"
        case salaryHourlyMin = "salary_hourly_min"
        case salaryHourlyMax = "salary_hourly_max"
        case salaryCurrency = "salary_currency"
        case salaryNote = "salary_note"
        case employmentType = "employment_type"
        case niceToHaves = "nice_to_haves"
        case applicationUrl = "application_url"
        case applicationInstructions = "application_instructions"
    }
}

// MARK: - Fit score

@available(macOS 26.0, *)
@Generable
struct GeneratedFitDimension: Encodable {
    @Guide(description: "Dimension name") var name: String
    @Guide(description: "Score 0–100") var score: Int
    @Guide(description: "Weight 0–1") var weight: Double
    @Guide(description: "Short justification") var rationale: String
}

@available(macOS 26.0, *)
@Generable
struct GeneratedFit: Encodable {
    @Guide(description: "Overall fit score 0–100") var overall: Int
    @Guide(description: "Short overall justification, or null") var summary: String?
    @Guide(description: "Requirements the resume satisfies") var requirementsMet: [String]
    @Guide(description: "Requirements the resume does not satisfy") var requirementsNotMet: [String]
    @Guide(description: "One object per scoring dimension") var dimensions: [GeneratedFitDimension]

    enum CodingKeys: String, CodingKey {
        case overall, summary, dimensions
        case requirementsMet = "requirements_met"
        case requirementsNotMet = "requirements_not_met"
    }
}
