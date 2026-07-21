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
        XCTAssertEqual(LLMConstants.maxDescriptionChars, 48000)
        XCTAssertEqual(LLMConstants.maxResumeChars, 40000)
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
}

// swiftlint:enable line_length file_length
