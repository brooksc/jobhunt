import XCTest
@testable import JobhuntCore

final class PromptBuilderTests: XCTestCase {
    // MARK: - Extraction prompts

    func testExtractionPromptHasSystemAndUserMessages() {
        let messages = PromptBuilder.buildExtractionPrompt(
            description: "We are hiring a Swift developer.",
            url: "https://example.com/job",
            pageTitle: "Swift Developer - Example Corp"
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[1].role, "user")
    }

    func testExtractionSystemPromptContent() {
        let messages = PromptBuilder.buildExtractionPrompt(
            description: "desc",
            url: "https://example.com",
            pageTitle: "title"
        )
        XCTAssertTrue(messages[0].content.contains("structured job posting data"))
        XCTAssertTrue(messages[0].content.contains("JSON object"))
    }

    func testExtractionUserPromptContainsURL() {
        let messages = PromptBuilder.buildExtractionPrompt(
            description: "desc",
            url: "https://jobs.example.com/12345",
            pageTitle: "My Job"
        )
        XCTAssertTrue(messages[1].content.contains("https://jobs.example.com/12345"))
    }

    func testExtractionUserPromptContainsPageTitle() {
        let messages = PromptBuilder.buildExtractionPrompt(
            description: "desc",
            url: "https://example.com",
            pageTitle: "Senior Software Engineer"
        )
        XCTAssertTrue(messages[1].content.contains("Senior Software Engineer"))
    }

    func testExtractionUserPromptContainsDescriptionText() {
        let messages = PromptBuilder.buildExtractionPrompt(
            description: "We need 5 years of Swift experience.",
            url: "https://example.com",
            pageTitle: "title"
        )
        XCTAssertTrue(messages[1].content.contains("We need 5 years of Swift experience."))
    }

    func testDescriptionTruncatedAtMaxChars() {
        let longDesc = String(repeating: "a", count: LLMConstants.maxDescriptionChars + 1000)
        let messages = PromptBuilder.buildExtractionPrompt(
            description: longDesc,
            url: "https://example.com",
            pageTitle: "title"
        )
        // The user prompt should contain at most LLMConstants.maxDescriptionChars 'a' characters from the description
        let repeatedAs = String(repeating: "a", count: LLMConstants.maxDescriptionChars)
        XCTAssertTrue(messages[1].content.contains(repeatedAs))
        // Should NOT contain the extra characters
        XCTAssertFalse(messages[1].content.contains(String(
            repeating: "a",
            count: LLMConstants.maxDescriptionChars + 1
        )))
    }

    func testDescriptionUnderLimitNotTruncated() {
        let desc = String(repeating: "b", count: 100)
        let messages = PromptBuilder.buildExtractionPrompt(
            description: desc,
            url: "https://example.com",
            pageTitle: "title"
        )
        XCTAssertTrue(messages[1].content.contains(desc))
    }

    func testExtractionPromptContainsRequiredJSONKeys() {
        let messages = PromptBuilder.buildExtractionPrompt(
            description: "d",
            url: "u",
            pageTitle: "t"
        )
        let user = messages[1].content
        let requiredKeys = [
            "company",
            "title",
            "location",
            "remote_type",
            "salary_min",
            "salary_max",
            "employment_type",
            "skills",
            "requirements",
            "nice_to_haves",
            "benefits",
            "application_url",
            "confidence"
        ]
        for key in requiredKeys {
            XCTAssertTrue(user.contains(key), "Missing key: \(key)")
        }
    }

    func testLocationContextIncludedInPrompt() {
        let ctx = LocationContext(
            preferredLocations: "Seattle, WA",
            allowRemote: true,
            allowHybrid: false,
            allowOnsite: true
        )
        let messages = PromptBuilder.buildExtractionPrompt(
            description: "d",
            url: "u",
            pageTitle: "t",
            locationContext: ctx
        )
        let user = messages[1].content
        XCTAssertTrue(user.contains("Seattle, WA"))
        XCTAssertTrue(user.contains("Preferred locations"))
    }

    func testNoLocationContextGivesDefaultMessage() {
        let messages = PromptBuilder.buildExtractionPrompt(
            description: "d",
            url: "u",
            pageTitle: "t",
            locationContext: .none
        )
        let user = messages[1].content
        XCTAssertTrue(user.contains("No location preferences configured"))
    }

    // MARK: - Fit prompts

    func testFitPromptHasSystemAndUserMessages() {
        let messages = PromptBuilder.buildFitPrompt(
            extractedJob: ExtractedJobContext(title: "SWE"),
            resumeText: "I have 10 years experience."
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[1].role, "user")
    }

    func testFitSystemPromptContent() {
        let messages = PromptBuilder.buildFitPrompt(
            extractedJob: ExtractedJobContext(),
            resumeText: "resume"
        )
        XCTAssertTrue(messages[0].content.contains("recruiting analyst"))
        XCTAssertTrue(messages[0].content.contains("JSON object"))
    }

    func testFitUserPromptContainsDimensions() {
        let messages = PromptBuilder.buildFitPrompt(
            extractedJob: ExtractedJobContext(),
            resumeText: "r"
        )
        let user = messages[1].content
        XCTAssertTrue(user.contains("required_qualifications"))
        XCTAssertTrue(user.contains("preferred_qualifications"))
        XCTAssertTrue(user.contains("skills"))
        XCTAssertTrue(user.contains("experience_level"))
        XCTAssertTrue(user.contains("domain_fit"))
    }

    func testFitUserPromptContainsJobInfo() {
        let job = ExtractedJobContext(
            title: "Staff Engineer",
            company: "Acme Corp",
            requirements: ["5+ years Swift", "iOS experience"],
            skills: ["Swift", "SwiftUI"]
        )
        let messages = PromptBuilder.buildFitPrompt(extractedJob: job, resumeText: "r")
        let user = messages[1].content
        XCTAssertTrue(user.contains("Staff Engineer"))
        XCTAssertTrue(user.contains("Acme Corp"))
        XCTAssertTrue(user.contains("5+ years Swift"))
        XCTAssertTrue(user.contains("Swift"))
    }

    func testResumeTruncatedAtMaxChars() {
        let longResume = String(repeating: "r", count: LLMConstants.maxResumeChars + 500)
        let messages = PromptBuilder.buildFitPrompt(
            extractedJob: ExtractedJobContext(),
            resumeText: longResume
        )
        let repeatedRs = String(repeating: "r", count: LLMConstants.maxResumeChars)
        XCTAssertTrue(messages[1].content.contains(repeatedRs))
        XCTAssertFalse(messages[1].content.contains(String(repeating: "r", count: LLMConstants.maxResumeChars + 1)))
    }

    func testApplicationInstructionsIncludedWithLabel() {
        let job = ExtractedJobContext(
            title: "PM",
            applicationInstructions: "Include the word ORANGE in your cover letter"
        )
        let messages = PromptBuilder.buildFitPrompt(extractedJob: job, resumeText: "r")
        let user = messages[1].content
        XCTAssertTrue(user.contains("Include the word ORANGE"))
        XCTAssertTrue(user.contains("submission mechanics"))
    }

    // MARK: - Overhead measurement

    func testPromptOverheadCharsArePositive() {
        let overhead = PromptBuilder.promptOverheadChars()
        XCTAssertGreaterThan(overhead.extractChars, 0)
        XCTAssertGreaterThan(overhead.fitChars, 0)
    }

    func testPromptOverheadCharsWithLocationContext() {
        let ctx = LocationContext(preferredLocations: "NYC", allowRemote: true, allowHybrid: true, allowOnsite: true)
        let withCtx = PromptBuilder.promptOverheadChars(locationContext: ctx)
        let noCtx = PromptBuilder.promptOverheadChars(locationContext: .none)
        // With location context, extraction overhead should be larger
        XCTAssertGreaterThan(withCtx.extractChars, noCtx.extractChars)
    }
}

// MARK: - Culture / values requirements

/// Job #182 (Zip) listed "Alignment with Zip's core values" as a hard requirement, and the scorer
/// dutifully assessed the résumé as not meeting it. The posting never defines what would satisfy it
/// and a résumé cannot evidence it, so the assessment carries no information — it just reads as a
/// gap the candidate can't close.
final class ValuesRequirementPromptTests: XCTestCase {
    /// The whole prompt as the model receives it — the rules live in the user message, and which
    /// message carries them is an implementation detail these tests shouldn't pin.
    private var extractionPrompt: String {
        PromptBuilder.buildExtractionPrompt(description: "d", url: "u", pageTitle: "t")
            .map(\.content).joined(separator: "\n").lowercased()
    }

    private var fitPrompt: String {
        PromptBuilder.buildFitPrompt(extractedJob: ExtractedJobContext(), resumeText: "r")
            .map(\.content).joined(separator: "\n").lowercased()
    }

    /// Preferred fix: they never become requirements in the first place.
    func testExtractionIsToldNotToRecordValuesStatements() {
        let prompt = extractionPrompt
        XCTAssertTrue(prompt.contains("cultural fit"), "extraction must exclude culture/values statements")
        XCTAssertTrue(prompt.contains("core values"), "the instruction should give a concrete example")
    }

    /// Backstop: if one is already stored (or slips through), don't score against it.
    func testScoringIsToldToSkipValuesStatements() {
        let prompt = fitPrompt
        XCTAssertTrue(prompt.contains("cultural fit"))
        XCTAssertTrue(
            prompt.contains("omit them from requirement_assessments"),
            "a values statement must not appear as an assessed requirement"
        )
    }

    /// The exclusion must not swallow real qualifications that merely sound soft — those are
    /// evidenced in a résumé and belong in the assessment.
    func testSoftButConcreteQualificationsAreExplicitlyPreserved() {
        for prompt in [extractionPrompt, fitPrompt] {
            XCTAssertTrue(prompt.contains("communication"), "must carve out genuine soft skills")
            XCTAssertTrue(prompt.contains("leadership"))
        }
    }

    /// The existing submission-mechanics carve-out uses the same shape and must survive.
    func testSubmissionMechanicsExclusionIsIntact() {
        XCTAssertTrue(fitPrompt.contains("submission mechanics"))
    }
}
