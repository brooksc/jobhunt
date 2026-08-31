// swiftlint:disable line_length file_length
import XCTest
@testable import JobhuntCore

// MARK: - SalaryNormalizer Tests

final class SalaryNormalizerTests: XCTestCase {
    /// Helper to run normalization and extract result fields
    private func normalize(
        note: String? = nil,
        currency: String? = nil,
        salaryMin: Int? = nil,
        salaryMax: Int? = nil,
        preferredLocations: String? = nil,
        sourceText: String? = nil
    ) -> [String: Any?] {
        var extracted: [String: Any?] = [:]
        extracted["salary_note"] = note as Any?
        extracted["salary_currency"] = currency as Any?
        extracted["salary_min"] = salaryMin as Any?
        extracted["salary_max"] = salaryMax as Any?
        extracted["salary_hourly_min"] = nil
        extracted["salary_hourly_max"] = nil
        return SalaryNormalizer.normalize(
            extracted: extracted,
            preferredLocations: preferredLocations,
            sourceText: sourceText
        )
    }

    func testHourlyToAnnual2080Hours() {
        // Port of: 'computes annual salary from an hourly range using 2080 hours'
        let result = normalize(
            note: "Pay: $85/hr - $105/hr on W2 contract.",
            salaryMin: 174_800,
            salaryMax: 211_600
        )
        XCTAssertEqual(result["salary_currency"] as? String, "USD")
        XCTAssertEqual(result["salary_hourly_min"] as? Double, 85.0)
        XCTAssertEqual(result["salary_hourly_max"] as? Double, 105.0)
        XCTAssertEqual(result["salary_min"] as? Int, 176_800)
        XCTAssertEqual(result["salary_max"] as? Int, 218_400)
    }

    func testHourlyToAnnualWithoutSlashNotation() {
        // Port of: 'computes annual salary from hourly language without slash notation'
        let result = normalize(note: "Hourly compensation range is $72.50 to $90 per hour.")
        XCTAssertEqual(result["salary_hourly_min"] as? Double, 72.5)
        XCTAssertEqual(result["salary_hourly_max"] as? Double, 90.0)
        XCTAssertEqual(result["salary_min"] as? Int, 150_800)
        XCTAssertEqual(result["salary_max"] as? Int, 187_200)
    }

    func testHourlyWithCurrencyAfterNumber() {
        // Port of: 'computes annual salary from hourly ranges with currency after the number'
        let result = normalize(
            note: "50 - 150USD/Hr, based on experience and location",
            currency: "USD",
            salaryMin: 100_000,
            salaryMax: 300_000
        )
        XCTAssertEqual(result["salary_hourly_min"] as? Double, 50.0)
        XCTAssertEqual(result["salary_hourly_max"] as? Double, 150.0)
        XCTAssertEqual(result["salary_min"] as? Int, 104_000)
        XCTAssertEqual(result["salary_max"] as? Int, 312_000)
    }

    func testAnnualSalaryFromNote() {
        // Port of: 'uses the low and high annual money values from the salary note'
        let result = normalize(
            note: "Salary range: $185,000 - $245,000 USD base salary.",
            salaryMin: 120_000,
            salaryMax: 220_000
        )
        XCTAssertEqual(result["salary_min"] as? Int, 185_000)
        XCTAssertEqual(result["salary_max"] as? Int, 245_000)
    }

    func testAnnualValuesWithCurrencyBeforeAndAfter() {
        // Port of: 'parses annual values with currency before and after the range'
        let result = normalize(note: "USD114,000.00 - $148,000.00")
        XCTAssertEqual(result["salary_min"] as? Int, 114_000)
        XCTAssertEqual(result["salary_max"] as? Int, 148_000)
    }

    func testCompactAnnualRangeWithCurrencyPrefix() {
        // Port of: 'parses compact annual ranges with currency prefix'
        let result = normalize(note: "USD179000–210000 Annually")
        XCTAssertEqual(result["salary_min"] as? Int, 179_000)
        XCTAssertEqual(result["salary_max"] as? Int, 210_000)
    }

    func testAnnualRangeWithCurrencyAfterSecondValue() {
        // Port of: 'parses annual ranges with currency after the second value'
        let result =
            normalize(
                note: "San Francisco Bay Area: 133400 - 226600 USD Annual; All Other US Locations: 116000 - 197000 USD Annual."
            )
        XCTAssertEqual(result["salary_min"] as? Int, 116_000)
        XCTAssertEqual(result["salary_max"] as? Int, 226_600)
    }

    func testDoesNotMixCADIntoUSD() {
        // Port of: 'does not mix CAD salary bands into USD salary ranges'
        let result = normalize(
            note: "US employees (any location): $200,700 - $250,900; Canadian employees (any location): CAD 189,700 - 237,100",
            currency: "USD",
            salaryMin: 200_700,
            salaryMax: 250_900
        )
        XCTAssertEqual(result["salary_min"] as? Int, 200_700)
        XCTAssertEqual(result["salary_max"] as? Int, 250_900)
    }

    func testCompactKNotation() {
        // Port of: 'handles compact annual k notation'
        let result = normalize(note: "Base pay is $140k-$200k plus equity.")
        XCTAssertEqual(result["salary_min"] as? Int, 140_000)
        XCTAssertEqual(result["salary_max"] as? Int, 200_000)
    }

    func testDoesNotTreat401kBenefitInSourceAsSalary() {
        // Regression (job #163): a posting with NO salary but a "401k with employer match" benefit
        // must not be mined into a bogus $401,000 salary during source-text recovery.
        let result = normalize(
            note: nil,
            sourceText: "Benefits: 401k with employer match, unlimited PTO, health and wellness insurance."
        )
        XCTAssertNil(result["salary_min"] as? Int)
        XCTAssertNil(result["salary_max"] as? Int)
    }

    func testDoesNotTreat401kInNoteAsSalary() {
        // Same guard on the salary_note path (in case a model parks the benefit line in salary_note).
        let result = normalize(note: "401k with employer match; competitive compensation package")
        XCTAssertNil(result["salary_min"] as? Int)
        XCTAssertNil(result["salary_max"] as? Int)
    }

    func testCurrencyPrefixed401KSalaryStillParses() {
        // The benefit-token strip must not swallow a genuine currency-prefixed "$401K" salary.
        let result = normalize(note: "Compensation: $401K annually.")
        XCTAssertEqual(result["salary_min"] as? Int, 401_000)
        XCTAssertEqual(result["salary_max"] as? Int, 401_000)
    }

    func testMoneyAmountsIgnoresRetirementPlanTokens() {
        XCTAssertEqual(SalaryNormalizer.moneyAmounts("401k with employer match"), [])
        XCTAssertEqual(SalaryNormalizer.moneyAmounts("Roth 403(b) and 457(b) available"), [])
        // A real salary alongside a 401k benefit keeps only the salary.
        XCTAssertEqual(
            SalaryNormalizer.moneyAmounts("Base $140k-$200k, plus 401k match"),
            [140_000, 200_000]
        )
    }

    func testMultipleBandsUseLowestAndHighest() {
        // Port of: 'uses the lowest and highest values when a note includes multiple annual bands'
        let result = normalize(
            note: "Salary range: $185,000 - $245,000 USD base salary. San Francisco and New York range: $210,000 - $285,000 USD.",
            salaryMin: 185_000,
            salaryMax: 245_000
        )
        XCTAssertEqual(result["salary_min"] as? Int, 185_000)
        XCTAssertEqual(result["salary_max"] as? Int, 285_000)
    }

    func testPreferredStateSpecificBand() {
        // Port of: 'uses a preferred state-specific annual band when one matches'
        let note = """
        CA, NY, CT, NJ
        $214,000-$216,500 USD
        WA
        $205,000-$216,500 USD
        All other states
        $178,000-$188,000 USD
        """
        let result = normalize(
            note: note,
            currency: "USD",
            salaryMin: 178_000,
            salaryMax: 216_500,
            preferredLocations: "Seattle, WA, Remote, United States"
        )
        XCTAssertEqual(result["salary_min"] as? Int, 205_000)
        XCTAssertEqual(result["salary_max"] as? Int, 216_500)
    }

    func testSourceTextPreferredBand() {
        // Port of: 'uses source text for preferred state-specific bands when the model salary note omits labels'
        let sourceText = """
        CA, NY, CT, NJ
        $214,000-$216,500 USD
        WA
        $205,000-$216,500 USD
        All other states
        $178,000-$188,000 USD
        """
        let result = normalize(
            note: "$214,000-$216,500 USD; $205,000-$216,500 USD; $178,000-$188,000 USD",
            currency: "USD",
            salaryMin: 214_000,
            salaryMax: 216_500,
            preferredLocations: "Seattle, WA, Remote, United States",
            sourceText: sourceText
        )
        XCTAssertEqual(result["salary_min"] as? Int, 205_000)
        XCTAssertEqual(result["salary_max"] as? Int, 216_500)
    }

    func testGeneralUSBandWhenMetroDoesNotMatch() {
        // Port of: 'uses the general US band when specific metro bands do not match preferences'
        let note = "The typical base pay range for this role across the U.S. is USD $119,800 - $234,700 per year. There is a different range applicable to specific work locations, within the San Francisco Bay area and New York City metropolitan area, and the base pay range for this role in those locations is USD $158,400 - $258,000 per year."
        let result = normalize(
            note: note,
            currency: "USD",
            salaryMin: 119_800,
            salaryMax: 258_000,
            preferredLocations: "Seattle, WA, Remote, United States"
        )
        XCTAssertEqual(result["salary_min"] as? Int, 119_800)
        XCTAssertEqual(result["salary_max"] as? Int, 234_700)
    }

    func testMixedUSDCADNormalizesToUSD() {
        // Port of: 'normalizes mixed USD/CAD currency output to the USD salary band'
        let result = normalize(
            note: "US employees (any location): $200,700 - $250,900; Canadian employees (any location): CAD 189,700 - 237,100",
            currency: "USD/CAD",
            salaryMin: 189_700,
            salaryMax: 250_900
        )
        XCTAssertEqual(result["salary_currency"] as? String, "USD")
        XCTAssertEqual(result["salary_min"] as? Int, 200_700)
        XCTAssertEqual(result["salary_max"] as? Int, 250_900)
    }

    func testWorkdayMultiBandNote() {
        // Port of: 'parses Workday multi-band salary_note (comma-separated thousands, USD Annual)'
        let result =
            normalize(
                note: "San Francisco Bay Area:\n133,400 - 226,600 USD Annual\nAll Other US Locations:\n116,000 - 197,000 USD Annual"
            )
        XCTAssertEqual(result["salary_currency"] as? String, "USD")
        XCTAssertEqual(result["salary_min"] as? Int, 116_000)
        XCTAssertEqual(result["salary_max"] as? Int, 226_600)
    }

    func testRecoverWorkdaySalaryFromSourceText() {
        // Port of: 'recovers Workday salary from sourceText when LLM returns null salary_note'
        let workdayPageFragment = """
        The base pay range varies based on geographic location.
        San Francisco Bay Area:
        133,400 - 226,600 USD Annual
        All Other US Locations:
        116,000 - 197,000 USD Annual
        """
        let result = normalize(sourceText: workdayPageFragment)
        XCTAssertEqual(result["salary_currency"] as? String, "USD")
        XCTAssertEqual(result["salary_min"] as? Int, 116_000)
        XCTAssertEqual(result["salary_max"] as? Int, 226_600)
    }

    func testRecoverWorkdaySalaryWithPreferredLocation() {
        // Port of: 'recovers Workday salary from sourceText respecting preferred location band'
        let workdayPageFragment = """
        San Francisco Bay Area:
        133,400 - 226,600 USD Annual
        All Other US Locations:
        116,000 - 197,000 USD Annual
        """
        let result = normalize(preferredLocations: "San Francisco, CA", sourceText: workdayPageFragment)
        XCTAssertEqual(result["salary_currency"] as? String, "USD")
        XCTAssertEqual(result["salary_min"] as? Int, 133_400)
        XCTAssertEqual(result["salary_max"] as? Int, 226_600)
    }

    func testSelectAllOtherUSBandFromCleanedWorkdaySource() {
        // Port of: 'selects All Other US band from cleaned Workday sourceText when user is outside SF'
        let cleanedFragment = """
        San Francisco Bay Area: 133,400 - 226,600 USD Annual
        All Other US Locations: 116,000 - 197,000 USD Annual
        """
        let result = normalize(
            preferredLocations: "Seattle, WA, Remote, United States",
            sourceText: cleanedFragment
        )
        XCTAssertEqual(result["salary_currency"] as? String, "USD")
        XCTAssertEqual(result["salary_min"] as? Int, 116_000)
        XCTAssertEqual(result["salary_max"] as? Int, 197_000)
    }

    func testDifferentRangeBranchWithAllOtherUS() {
        // Port of: "covers 'different range' note branch when All Other US band is present"
        var extracted: [String: Any?] = [:]
        extracted["salary_note"] =
            "San Francisco Bay Area:\n$180,000 - $220,000 USD Annual\nAll Other US Locations:\n$100,000 - $200,000 USD Annual\ndifferent range applicable to specific work locations" as Any?
        let result = SalaryNormalizer.normalize(extracted: extracted)
        XCTAssertEqual(result["salary_min"] as? Int, 100_000)
        XCTAssertEqual(result["salary_max"] as? Int, 200_000)
    }
}

// MARK: - RemoteTypeInferer Tests

final class RemoteTypeInferrerTests: XCTestCase {
    private func normalize(_ extracted: [String: Any?], description: String?, url: String? = nil) -> [String: Any?] {
        RemoteTypeInferer.normalize(extracted: extracted, description: description, url: url)
    }

    func testRemoteOrHybridTextTreatedAsRemote() {
        // Port of: 'treats Remote or Hybrid as remote before location filtering'
        let extracted: [String: Any?] = ["remote_type": "hybrid" as Any?]
        let description = """
        Title: Technical Program Manager, Research
        Work arrangement: Remote (telecommute)
        Hiring location: CAN; USA
        Location: USA; California, USA
        Work arrangement: Hybrid
        Remote or Hybrid
        """
        let result = normalize(extracted, description: description)
        XCTAssertEqual(result["remote_type"] as? String, "remote")
    }

    func testJobLocationTypeTelecommute() {
        // Port of: 'uses raw capture source when cleaned text omits the remote badge'
        let extracted: [String: Any?] = ["remote_type": "unknown" as Any?]
        let source = """
        Title: Technical Program Manager, Research
        Location: USA
        Remote
        Hiring Remotely in USA
        {"jobLocationType":"TELECOMMUTE"}
        """
        let result = normalize(extracted, description: source)
        XCTAssertEqual(result["remote_type"] as? String, "remote")
    }

    func testLevelsFyiRemoteURLParam() {
        // Port of: 'uses Levels.fyi remote filter parameters as a remote signal'
        let extracted: [String: Any?] = [
            "remote_type": "unknown" as Any?,
            "location": nil,
            "company": "Zscaler" as Any?
        ]
        let result = normalize(
            extracted,
            description: "Sr. Staff Technical Program Manager - DoW\nZscaler\nRole",
            url: "https://www.levels.fyi/jobs/title/technical-program-manager?jobId=138073367340032710&perkIds=58"
        )
        XCTAssertEqual(result["remote_type"] as? String, "remote")
    }

    func testIndeedRemoteURLParam() {
        // Port of: 'covers urlIndicatesRemote TRUE path for Indeed remote URL'
        let extracted: [String: Any?] = ["remote_type": "onsite" as Any?]
        let result = normalize(
            extracted,
            description: "No remote indicators in text",
            url: "https://www.indeed.com/jobs?remotejob=1&q=engineer"
        )
        XCTAssertEqual(result["remote_type"] as? String, "remote")
    }

    func testNonRemoteURLNotInferred() {
        // Port of: 'covers urlIndicatesRemote return false path for non-remote URL'
        let extracted: [String: Any?] = ["remote_type": "onsite" as Any?]
        let result = normalize(
            extracted,
            description: "Onsite only role",
            url: "https://jobs.example.com/engineer?ref=board"
        )
        XCTAssertEqual(result["remote_type"] as? String, "onsite")
    }

    func testOpenToRemoteCandidatesLanguage() {
        // Port of: 'treats explicit remote-candidate language as remote'
        let extracted: [String: Any?] = ["remote_type": "unknown" as Any?]
        let result = normalize(
            extracted,
            description: "This is a hybrid role based in San Jose, CA (3 days onsite). While local candidates are preferred, we are open to remote candidates based on the West Coast for exceptional applicants."
        )
        XCTAssertEqual(result["remote_type"] as? String, "remote")
    }

    func testMicrosoft0DaysInOfficeIsRemote() {
        // Port of: 'infers Microsoft 0 days in-office as remote'
        let extracted: [String: Any?] = ["remote_type": "unknown" as Any?]
        let result = normalize(
            extracted,
            description: "Work site\n0 days / week in-office"
        )
        XCTAssertEqual(result["remote_type"] as? String, "remote")
    }

    func testMicrosoftOfficeDaysIsHybrid() {
        // Port of: 'infers Microsoft office-days work site as hybrid'
        let extracted: [String: Any?] = ["remote_type": "unknown" as Any?]
        let result = normalize(
            extracted,
            description: "Work site\n4 days / week in-office"
        )
        XCTAssertEqual(result["remote_type"] as? String, "hybrid")
    }

    func testAlreadyRemoteNotChanged() {
        let extracted: [String: Any?] = ["remote_type": "remote" as Any?]
        let result = normalize(extracted, description: "Onsite only.")
        XCTAssertEqual(result["remote_type"] as? String, "remote")
    }
}

// MARK: - LocationInferer Tests

final class LocationInferrerTests: XCTestCase {
    private func normalize(_ extracted: [String: Any?], description: String?) -> [String: Any?] {
        LocationInferer.normalize(extracted: extracted, description: description)
    }

    func testRecoverLocationFromMetadataLines() {
        // Port of: 'recovers location from metadata lines'
        let extracted: [String: Any?] = [
            "company": "Microsoft" as Any?,
            "title": "Senior Product Manager" as Any?,
            "location": nil,
            "remote_type": "unknown" as Any?
        ]
        let result = normalize(
            extracted,
            description: "Title: Senior Product Manager\nLocation: United States, Multiple Locations, Multiple Locations\nWork site: 0 days / week in-office - remote"
        )
        XCTAssertEqual(result["location"] as? String, "United States, Multiple Locations, Multiple Locations")
    }

    func testRemoteLocationWhenNoPhysical() {
        // Port of: 'uses Remote as location when the source has no physical location but is fully remote'
        let extracted: [String: Any?] = [
            "company": "Reddit" as Any?,
            "title": "Principal Technical Program Manager" as Any?,
            "location": nil,
            "remote_type": "unknown" as Any?
        ]
        let result = normalize(
            extracted,
            description: "Principal Technical Program Manager\nReddit · 8 days ago · Fully Remote"
        )
        XCTAssertEqual(result["location"] as? String, "Remote")
    }

    func testRecoverCityStateFromLineAfterTitle() {
        // Port of: 'recovers city/state location from the line after the title'
        let extracted: [String: Any?] = [
            "company": "Pinterest" as Any?,
            "title": "Technical Program Manager II, Platforms" as Any?,
            "location": nil,
            "remote_type": "unknown" as Any?
        ]
        let result = normalize(
            extracted,
            description: "Technical Program Manager II, Platforms\nSan Francisco, CA\n$103,965 - $214,044 a year"
        )
        XCTAssertEqual(result["location"] as? String, "San Francisco, CA")
    }

    func testRecoverLocationFromHybridBasedInLanguage() {
        // Port of: 'recovers location from hybrid role based-in language'
        let extracted: [String: Any?] = [
            "company": "Zscaler" as Any?,
            "title": "Senior Product Manager" as Any?,
            "location": nil,
            "remote_type": "unknown" as Any?
        ]
        let result = normalize(
            extracted,
            description: "This is a hybrid role based in San Jose, CA (3 days onsite). While local candidates are preferred, we are open to remote candidates based on the West Coast."
        )
        XCTAssertEqual(result["location"] as? String, "San Jose, CA")
    }

    func testRemoteCountryContext() {
        // Port of: 'preserves remote country context from source text'
        let extracted: [String: Any?] = [
            "company": "Instacart" as Any?,
            "title": "Senior Technical Program Manager" as Any?,
            "location": nil,
            "remote_type": "remote" as Any?
        ]
        let result = normalize(
            extracted,
            description: "Instacart\nSenior Technical Program Manager\nRemote - United States\nRole details"
        )
        XCTAssertEqual(result["location"] as? String, "Remote - United States")
    }

    func testExpandsBareRemoteWithCountryContext() {
        // Port of: 'expands bare remote location when source has country context'
        let extracted: [String: Any?] = [
            "company": "Mercury" as Any?,
            "title": "Senior Product Manager" as Any?,
            "location": "Remote" as Any?,
            "remote_type": "remote" as Any?
        ]
        let result = normalize(
            extracted,
            description: "Mercury\nSenior Product Manager\nRemote - United States or Canada\nRole details"
        )
        XCTAssertEqual(result["location"] as? String, "Remote - United States or Canada")
    }

    func testOverridesBareCountryWithRemote() {
        // Port of: 'overrides bare country location with Remote when source has Remote line'
        let extracted: [String: Any?] = [
            "company": "Google Fiber" as Any?,
            "title": "Senior TPM" as Any?,
            "location": "USA" as Any?,
            "remote_type": "remote" as Any?
        ]
        let result = normalize(extracted, description: "Remote\nHiring Remotely in USA")
        XCTAssertEqual(result["location"] as? String, "Remote")
    }

    func testNoLocationFoundNonRemote() {
        // Port of: 'returns extracted unchanged when no location found and source is not remote'
        let extracted: [String: Any?] = ["company": "Acme" as Any?, "title": "Engineer" as Any?]
        let result = normalize(extracted, description: "Competitive salary, great benefits. No remote.")
        XCTAssertEqual(result["company"] as? String, "Acme")
        XCTAssertNil(result["location"] as? String)
    }

    func testNoLocationFoundButRemote() {
        // Port of: 'returns Remote when no location found but source indicates remote (telecommute)'
        let extracted: [String: Any?] = ["company": "Acme" as Any?, "title": "Engineer" as Any?]
        let result = normalize(extracted, description: "Fully remote/telecommute position available for this role.")
        XCTAssertEqual(result["location"] as? String, "Remote")
    }

    // TASK-475: empty/whitespace description must not trap the 0..<(count-1) range.
    func testSourceLocationFromTitle_emptyDescriptionDoesNotTrap() {
        XCTAssertNil(LocationInferer.sourceLocationFromTitle("", title: "Engineer"))
        XCTAssertNil(LocationInferer.sourceLocationFromTitle(nil, title: "Engineer"))
        XCTAssertNil(LocationInferer.sourceLocationFromTitle("   \n  \n ", title: "Engineer"))
    }
}

// MARK: - CompanyBackfiller Tests

final class CompanyBackfillerTests: XCTestCase {
    func testRecoverCompanyFromStructuredData() {
        // Port of: 'recovers company from structured JobPosting data'
        let extracted: [String: Any?] = [
            "company": nil,
            "title": "Adobe Commerce Technical Program Manager (TPM)" as Any?
        ]
        let description = #""hiringOrganization":{"@type":"Organization","name":"Blue Acorn iCi","sameAs":"https://builtin.com/company/blue-acorn-ici"}"#
        let result = CompanyBackfiller.normalize(extracted: extracted, description: description)
        XCTAssertEqual(result["company"] as? String, "Blue Acorn iCi")
    }

    func testDoesNotOverwriteExistingCompany() {
        let extracted: [String: Any?] = ["company": "Existing Co" as Any?]
        let description = #""hiringOrganization":{"name":"Other Co"}"#
        let result = CompanyBackfiller.normalize(extracted: extracted, description: description)
        XCTAssertEqual(result["company"] as? String, "Existing Co")
    }
}

// MARK: - DisplayNormalizer Tests

final class DisplayNormalizerTests: XCTestCase {
    func testMapStatus() {
        // Canonical values pass through unchanged
        XCTAssertEqual(DisplayNormalizer.mapStatus("pursuing"), "pursuing")
        XCTAssertEqual(DisplayNormalizer.mapStatus("applied"), "applied")
        XCTAssertEqual(DisplayNormalizer.mapStatus("offer"), "offer")
        XCTAssertEqual(DisplayNormalizer.mapStatus("rejected"), "rejected")
        XCTAssertEqual(DisplayNormalizer.mapStatus("archived"), "archived")
        XCTAssertEqual(DisplayNormalizer.mapStatus("passed"), "passed")
        XCTAssertEqual(DisplayNormalizer.mapStatus("closed"), "closed")
        XCTAssertEqual(DisplayNormalizer.mapStatus("duplicate"), "duplicate")
        // Legacy → new mappings
        XCTAssertEqual(DisplayNormalizer.mapStatus("saved"), "pursuing")
        XCTAssertEqual(DisplayNormalizer.mapStatus("interested"), "pursuing")
        XCTAssertEqual(DisplayNormalizer.mapStatus("interviewing"), "interview")
        XCTAssertEqual(DisplayNormalizer.mapStatus("ignored"), "passed")
        // Unknown passes through
        XCTAssertEqual(DisplayNormalizer.mapStatus("unknown_status"), "unknown_status")
    }

    func testMapRemote() {
        // Port of transform.test.js 'mapRemote' suite
        XCTAssertEqual(DisplayNormalizer.mapRemote("remote"), "Remote")
        XCTAssertEqual(DisplayNormalizer.mapRemote("hybrid"), "Hybrid")
        XCTAssertEqual(DisplayNormalizer.mapRemote("onsite"), "Onsite")
        XCTAssertEqual(DisplayNormalizer.mapRemote("unknown"), "—")
        XCTAssertEqual(DisplayNormalizer.mapRemote(nil), "—")
        XCTAssertEqual(DisplayNormalizer.mapRemote(""), "—")
    }

    func testMapEmployment() {
        // Port of transform.test.js 'mapEmployment' suite
        XCTAssertEqual(DisplayNormalizer.mapEmployment("full_time"), "Full-time")
        XCTAssertEqual(DisplayNormalizer.mapEmployment("fulltime"), "Full-time")
        XCTAssertEqual(DisplayNormalizer.mapEmployment("full-time"), "Full-time")
        XCTAssertEqual(DisplayNormalizer.mapEmployment(nil), "—")
    }

    func testMapExtractionStatus() {
        XCTAssertEqual(DisplayNormalizer.mapExtractionStatus("succeeded"), "ok")
        XCTAssertEqual(DisplayNormalizer.mapExtractionStatus("failed"), "fail")
        XCTAssertEqual(DisplayNormalizer.mapExtractionStatus("pending"), "pending")
        XCTAssertEqual(DisplayNormalizer.mapExtractionStatus(nil), "pending")
    }

    func testToStringArray() {
        // Port of transform.test.js 'toStringArray' suite
        XCTAssertEqual(DisplayNormalizer.toStringArray(["a", "b"]) as? [String], ["a", "b"])
        XCTAssertEqual(
            DisplayNormalizer.toStringArray("Must have 5 years exp.") as? [String],
            ["Must have 5 years exp."]
        )
        XCTAssertEqual(DisplayNormalizer.toStringArray(nil) as? [String], [])
        XCTAssertEqual(DisplayNormalizer.toStringArray("") as? [String], [])
    }
}

// MARK: - LLMConstants Tests

final class LLMConstantsTests: XCTestCase {
    func testConstants() {
        XCTAssertEqual(LLMConstants.maxDescriptionChars, 100_000)
        XCTAssertEqual(LLMConstants.maxResumeChars, 100_000)
    }
}

// MARK: - JobFieldNormalizer Tests

final class JobFieldNormalizerTests: XCTestCase {
    func testComposesAllNormalizationPasses() {
        let normalizer = JobFieldNormalizer()
        var extracted: [String: Any?] = [
            "company": nil,
            "title": "Senior Engineer" as Any?,
            "location": nil,
            "remote_type": "unknown" as Any?,
            "salary_note": "$120k - $150k" as Any?,
            "salary_currency": nil,
            "salary_min": nil,
            "salary_max": nil,
            "salary_hourly_min": nil,
            "salary_hourly_max": nil
        ]
        let source = """
        Senior Engineer
        San Francisco, CA
        "hiringOrganization":{"name":"Acme Corp"}
        """
        let result = normalizer.normalize(extracted: extracted, sourceText: source)
        // CompanyBackfiller should fill company
        XCTAssertEqual(result["company"] as? String, "Acme Corp")
        // LocationInferer should fill location
        XCTAssertEqual(result["location"] as? String, "San Francisco, CA")
        // SalaryNormalizer should parse salary
        XCTAssertNotNil(result["salary_min"])
        XCTAssertNotNil(result["salary_max"])
    }

    // MARK: - Trapping-conversion hardening (F12/F13)

    func testBoundedSalaryIntNeverTrapsAndClamps() {
        // `Int(Double)` aborts the process for out-of-range/non-finite values (CWE-190); the guarded
        // helper must clamp instead of crash.
        XCTAssertEqual(SalaryNormalizer.boundedSalaryInt(150_000), 150_000, "normal value unchanged")
        XCTAssertEqual(SalaryNormalizer.boundedSalaryInt(1e20), 1_000_000_000, "absurd amount clamps")
        XCTAssertEqual(SalaryNormalizer.boundedSalaryInt(.infinity), 0)
        XCTAssertEqual(SalaryNormalizer.boundedSalaryInt(.nan), 0)
        XCTAssertEqual(SalaryNormalizer.boundedSalaryInt(-5), 0)
    }

    func testNormalizeDoesNotTrapOnAbsurdSalaryInSourceText() {
        // A ~20-digit salary in untrusted capture text used to trap the process at Int(Double);
        // reaching the assertions at all proves the crash is gone.
        let out = SalaryNormalizer.normalize(
            extracted: ["salary_note": ""],
            sourceText: "Compensation: $99999999999999999999 per year"
        )
        if let minVal = out["salary_min"] as? Int {
            XCTAssertLessThanOrEqual(minVal, 1_000_000_000)
        }
    }
}

// swiftlint:enable line_length file_length

/// The app crashed — SIGTRAP, whole process — on capturing a Netflix posting. Its board writes
/// `?…&Teams=Engineering&Teams=Engineering%20Operations`, a legitimately repeated query parameter,
/// and `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key. The extraction died with the
/// process and the job was left stuck in `running`, which read as "Netflix jobs don't parse".
final class RemoteURLDuplicateParameterTests: XCTestCase {
    /// The exact shape that crashed.
    func testRepeatedQueryParameterDoesNotTrap() {
        let netflix = "https://explore.jobs.netflix.net/careers?query=Technical%20Program%20Manager"
            + "&location=any&pid=790316311096&Teams=Engineering&Teams=Engineering%20Operations"
        XCTAssertFalse(RemoteTypeInferer.urlIndicatesRemote(netflix))
    }

    /// Repetition anywhere in the query must be survivable, not just on one board.
    func testRepeatedParametersOnAnyHost() {
        for url in [
            "https://example.com/jobs?tag=a&tag=b",
            "https://example.com/jobs?utm_source=x&utm_source=y&utm_source=z",
            "https://www.linkedin.com/jobs/search?f_WT=1&f_WT=2&f_WT=3",
            "https://www.indeed.com/jobs?l=Remote&l=Austin"
        ] {
            // The assertion is that this returns at all — each of these used to abort the process.
            _ = RemoteTypeInferer.urlIndicatesRemote(url)
        }
    }

    /// Every value counts, not just the last one: a board expresses "remote OR onsite" as a repeated
    /// filter, and a last-one-wins dictionary would have reported whichever came last.
    func testRemoteSignalIsFoundAmongRepeatedValues() {
        XCTAssertTrue(
            RemoteTypeInferer.urlIndicatesRemote("https://www.linkedin.com/jobs/search?f_WT=1&f_WT=2"),
            "f_WT=2 means remote whether or not it is the last value"
        )
        XCTAssertTrue(
            RemoteTypeInferer.urlIndicatesRemote("https://www.linkedin.com/jobs/search?f_WT=2&f_WT=1")
        )
        XCTAssertTrue(
            RemoteTypeInferer.urlIndicatesRemote("https://www.indeed.com/jobs?l=Austin&l=Remote")
        )
        XCTAssertFalse(
            RemoteTypeInferer.urlIndicatesRemote("https://www.linkedin.com/jobs/search?f_WT=1&f_WT=3")
        )
    }

    /// levels.fyi packs several perks into one comma-separated value, and can repeat the parameter.
    func testCommaSeparatedPerksAcrossRepeatedParameters() {
        XCTAssertTrue(
            RemoteTypeInferer.urlIndicatesRemote("https://www.levels.fyi/jobs?perkIds=12,58&perkIds=7")
        )
        XCTAssertTrue(
            RemoteTypeInferer.urlIndicatesRemote("https://www.levels.fyi/jobs?perkIds=7&perkIds=58")
        )
        XCTAssertFalse(
            RemoteTypeInferer.urlIndicatesRemote("https://www.levels.fyi/jobs?perkIds=7&perkIds=12")
        )
    }

    /// A parameter with no value at all must not throw the parse off either.
    func testValuelessParameters() {
        XCTAssertFalse(RemoteTypeInferer.urlIndicatesRemote("https://example.com/jobs?flag&flag&x=1"))
    }
}

/// GitHub's board writes "USD $140,400.00 - USD $372,300.00 /Yr." — the currency code repeats on both
/// sides of the dash. No range pattern allowed that, so the range never parsed as a range; the values
/// only survived as loose single amounts, and the whole-page fallback then took the smallest money on
/// the page. A posting with a signing bonus came out as "$5,000 - $372,300".
final class CurrencyRepeatedOnBothSidesTests: XCTestCase {
    /// The sentence exactly as github.careers publishes it, with the surrounding page money that made
    /// the old fallback wrong.
    private let githubPage = """
    Compensation Range
    The base salary range for this job is USD $140,400.00 - USD $372,300.00 /Yr.
    These pay ranges are intended to cover roles based across the United States.
    Employees are eligible for a $5,000 signing bonus. 401k with employer match.
    """

    func testRangeParsesAsARange() {
        let bands = SalaryNormalizer.salaryBands(githubPage)
        XCTAssertEqual(bands.count, 1)
        XCTAssertEqual(bands.first?.min, 140_400)
        XCTAssertEqual(bands.first?.max, 372_300)
    }

    /// The bug as the user would see it: no salary_note from the model, so the source text decides.
    func testSigningBonusDoesNotBecomeTheSalaryFloor() {
        let out = SalaryNormalizer.normalize(extracted: ["salary_note": ""], sourceText: githubPage)
        XCTAssertEqual(out["salary_min"] as? Int, 140_400, "the $5,000 bonus must not be read as the floor")
        XCTAssertEqual(out["salary_max"] as? Int, 372_300)
    }

    /// The same when the model does return the note.
    func testParsesFromTheSalaryNote() {
        let out = SalaryNormalizer.normalize(
            extracted: ["salary_note": "USD $140,400.00 - USD $372,300.00 /Yr."]
        )
        XCTAssertEqual(out["salary_min"] as? Int, 140_400)
        XCTAssertEqual(out["salary_max"] as? Int, 372_300)
    }

    /// Every way a board writes a repeated currency code, including en/em dashes and k-notation.
    func testRepeatedCurrencyVariants() {
        let cases: [(String, Int, Int)] = [
            ("USD $140,400.00 - USD $372,300.00", 140_400, 372_300),
            ("USD $140,400.00 – USD $372,300.00", 140_400, 372_300),
            ("USD $140,400.00 — USD $372,300.00", 140_400, 372_300),
            ("USD 140,400 - USD 372,300", 140_400, 372_300),
            ("$140K - USD $372K", 140_000, 372_000),
            ("EUR €90,000 - EUR €120,000", 90000, 120_000)
        ]
        for (note, low, high) in cases {
            let out = SalaryNormalizer.normalize(extracted: ["salary_note": note])
            XCTAssertEqual(out["salary_min"] as? Int, low, "min wrong for \(note)")
            XCTAssertEqual(out["salary_max"] as? Int, high, "max wrong for \(note)")
        }
    }

    /// A single parsed band is now preferred over the loose whole-text scan, but a range still has to
    /// look like money: "3 - 5 years of experience" must not become a salary.
    func testExperienceRangesAreStillNotSalaries() {
        let out = SalaryNormalizer.normalize(
            extracted: ["salary_note": ""],
            sourceText: "We want 3 - 5 years of experience and 2 - 4 years managing teams."
        )
        XCTAssertNil(out["salary_min"] as? Int)
        XCTAssertNil(out["salary_max"] as? Int)
    }
}

/// Job #1502 (SageSure) states no pay anywhere and was stored as `salary_min: 2020,
/// salary_max: 2023` — read out of "Best Places to Work in Insurance … for four years in a row
/// (2020-2023)". The inline range pattern in `salaryBands` had every currency marker optional, so it
/// degenerated to `\d+ - \d+`, and the only filter left was the ">= 1000 on both ends" magnitude
/// floor. A floor can't tell a year from a wage, so a match now has to carry pay evidence.
final class InventedSalaryBandTests: XCTestCase {
    private let sageSure = """
    Senior Product Manager. Named among the Best Places to Work in Insurance by Business Insurance \
    for four years in a row (2020-2023). We look for 5-7 years of product management experience.
    """

    func testYearRangeIsNotASalaryBand() {
        XCTAssertEqual(SalaryNormalizer.salaryBands(sageSure).count, 0)
    }

    func testPostingWithNoStatedPayNormalizesToNoSalary() {
        let out = SalaryNormalizer.normalize(extracted: ["salary_note": ""], sourceText: sageSure)
        XCTAssertNil(out["salary_min"] as? Int, "a year range must not become a salary")
        XCTAssertNil(out["salary_max"] as? Int)
    }

    /// Rounded for display, "2016-2017" is the "$2k–2k" several Elastic postings were showing.
    func testAnyBareYearPairIsRejected() {
        for years in ["2016-2017", "2019 - 2024", "1999–2001"] {
            XCTAssertEqual(
                SalaryNormalizer.salaryBands("Awarded every year (\(years)).").count, 0, years
            )
        }
    }

    /// These were rejected before only because both ends fell under the 1,000 floor. They must stay
    /// rejected — note that "annually" puts pay wording in the second sentence.
    func testExperienceAndPercentageRangesStayRejected() {
        XCTAssertEqual(SalaryNormalizer.salaryBands("5-7 years of product management experience").count, 0)
        XCTAssertEqual(SalaryNormalizer.salaryBands("Bonus is estimated at approximately 10–15% annually.").count, 0)
    }

    // MARK: - Real pay must still parse

    func testCurrencyMarkedRangesStillParse() {
        let cases: [(String, Int, Int)] = [
            ("USD $140,400.00 - USD $372,300.00 /Yr.", 140_400, 372_300),
            ("$150,000 - $210,000 per year", 150_000, 210_000),
            ("The range is 116,000 - 197,000 USD Annual", 116_000, 197_000),
            ("$140K - $180K", 140_000, 180_000)
        ]
        for (note, low, high) in cases {
            let out = SalaryNormalizer.normalize(extracted: ["salary_note": note])
            XCTAssertEqual(out["salary_min"] as? Int, low, note)
            XCTAssertEqual(out["salary_max"] as? Int, high, note)
        }
    }

    func testHourlyRangeStillParses() {
        let out = SalaryNormalizer.normalize(extracted: ["salary_note": "$45.00 - $60.00 per hour"])
        XCTAssertEqual(out["salary_hourly_min"] as? Double, 45)
        XCTAssertEqual(out["salary_hourly_max"] as? Double, 60)
        XCTAssertEqual(out["salary_min"] as? Int, 45 * 2080)
        XCTAssertEqual(out["salary_max"] as? Int, 60 * 2080)
    }

    /// A band with no currency marker at all is still pay when the sentence says so — the evidence
    /// requirement is about pay context, not about a dollar sign specifically.
    func testBareRangeWithPayWordingIsAccepted() {
        let bands = SalaryNormalizer.salaryBands("The base salary range for this role is 150,000 - 210,000.")
        XCTAssertEqual(bands.count, 1)
        XCTAssertEqual(bands.first?.min, 150_000)
        XCTAssertEqual(bands.first?.max, 210_000)
    }

    /// The real shape of the bug: a page that has BOTH a year range and a pay range must yield only
    /// the pay range — and the location-specific band selection must still work over it.
    func testLocationSpecificBandSurvivesAlongsideAYearRange() {
        let page = """
        Best Places to Work in Insurance (2020-2023).
        San Francisco Bay Area: 133,400 - 226,600 USD Annual
        All Other US Locations: 116,000 - 197,000 USD Annual
        """
        let bands = SalaryNormalizer.salaryBands(page)
        XCTAssertEqual(bands.count, 2, "the year range must not become a third band: \(bands.map(\.label))")

        let out = SalaryNormalizer.normalize(
            extracted: ["salary_note": ""], preferredLocations: "San Francisco, CA", sourceText: page
        )
        XCTAssertEqual(out["salary_min"] as? Int, 133_400)
        XCTAssertEqual(out["salary_max"] as? Int, 226_600)
    }
}
