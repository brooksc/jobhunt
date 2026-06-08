// swiftlint:disable line_length
// JDParserTests.swift — port of tests/unit/jd-parser.test.js
import XCTest
@testable import JobhuntCore

final class JDParserTests: XCTestCase {
    // MARK: - Empty / nil input

    func testReturnsEmptyArrayForEmptyString() {
        XCTAssertEqual(parseJdBlocks(""), [])
    }

    func testReturnsEmptyArrayForNil() {
        XCTAssertEqual(parseJdBlocks(nil), [])
    }

    // MARK: - Paragraphs

    func testProducesAParagraphBlockForPlainProse() {
        let blocks =
            parseJdBlocks("We are looking for an experienced engineer to join our team and build great products.")
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph = blocks[0] { } else { XCTFail("Expected paragraph, got \(blocks[0])") }
    }

    func testMergesConsecutiveNonEmptyLinesIntoOneParagraph() {
        let blocks = parseJdBlocks("Line one that is long enough to qualify.\nLine two continues the thought here.")
        let paras = blocks.filter { if case .paragraph = $0 { return true }; return false }
        XCTAssertEqual(paras.count, 1)
        if case let .paragraph(text) = paras[0] {
            XCTAssertTrue(text.contains("Line one"))
            XCTAssertTrue(text.contains("Line two"))
        }
    }

    func testSplitsOnBlankLinesIntoSeparateParagraphs() {
        let text = "First paragraph is long enough to be included.\n\nSecond paragraph also qualifies here."
        let paras = parseJdBlocks(text).filter { if case .paragraph = $0 { return true }; return false }
        XCTAssertEqual(paras.count, 2)
    }

    // MARK: - Headings

    func testDetectsAllCapsLineAsHeading() throws {
        let blocks = parseJdBlocks("We are hiring a great engineer.\n\nREQUIREMENTS\n\nSome requirement here.")
        let heading = blocks.first(where: { if case .heading = $0 { return true }; return false })
        XCTAssertNotNil(heading, "expected a heading block")
        if case let .heading(text) = try XCTUnwrap(heading) {
            XCTAssertEqual(text, "REQUIREMENTS")
        }
    }

    func testDetectsLineEndingInColonAsHeading() throws {
        let blocks = parseJdBlocks("We are hiring.\n\nWhat you will do:\n\nLead the team.")
        let heading = blocks.first(where: { if case .heading = $0 { return true }; return false })
        XCTAssertNotNil(heading)
        if case let .heading(text) = try XCTUnwrap(heading) {
            XCTAssertEqual(text, "What you will do")
        }
    }

    func testDetectsKnownKeywordLineAsHeading() {
        let blocks = parseJdBlocks("We are hiring.\n\nResponsibilities\n\nLead the team.")
        let heading = blocks.first(where: { if case .heading = $0 { return true }; return false })
        XCTAssertNotNil(heading)
    }

    // MARK: - Lists

    func testDetectsBulletLinesStartingWithBulletChar() throws {
        let blocks = parseJdBlocks("Requirements:\n• Five years experience\n• Strong communication")
        let list = blocks.first(where: { if case .list = $0 { return true }; return false })
        XCTAssertNotNil(list)
        if case let .list(items) = try XCTUnwrap(list) {
            XCTAssertEqual(items.count, 2)
            XCTAssertEqual(items[0], "Five years experience")
        }
    }

    func testDetectsBulletLinesStartingWithDash() throws {
        let blocks = parseJdBlocks("Skills:\n- Python\n- SQL")
        let list = blocks.first(where: { if case .list = $0 { return true }; return false })
        XCTAssertNotNil(list)
        if case let .list(items) = try XCTUnwrap(list) {
            XCTAssertEqual(items.count, 2)
        }
    }

    func testDetectsNumberedListItems() throws {
        let blocks = parseJdBlocks("Steps:\n1. Do this first\n2. Then do this")
        let list = blocks.first(where: { if case .list = $0 { return true }; return false })
        XCTAssertNotNil(list)
        if case let .list(items) = try XCTUnwrap(list) {
            XCTAssertEqual(items[0], "Do this first")
        }
    }

    // MARK: - LinkedIn regression (job-126)

    private var linkedInJD: String {
        // Inline the fixture so tests don't need file I/O
        """
        0 notifications
        Skip to search
        Skip to main content
        Skip to sidebar
        Skip to primary content
        Skip to aside
        Home
        1
        My Network
        Jobs
        Messaging
        1
        Notifications
        Me
        For Business
        Advertise

        Premium

        Brooks Cutter

        Technical Program Manager @ Meta | Ex-Microsoft Product/Program Manager | Driving AI Innovation & Digital Media Transformation

        Seattle, Washington

        Meta

        Profile viewers

        1,197

        Post impressions

        1,233

        Your Premium features

        Feed post

        Balu y

        • 3rd+

        IT Recruiter

        Visit my website

        8h •

        Follow

        🚀 Hiring: Technical Product Manager – Remote

        We are looking for an experienced Technical Product Manager with a strong healthcare background to join a dynamic team and drive the strategy, development, and delivery of healthcare technology platforms.

        📍 Location: Remote
        📌 Experience Required:
        • 12+ years of overall professional experience
        • 6+ years of Technical Product Management experience
        • 3+ years in Healthcare or HealthTech

        🔹 Key Responsibilities:
        • Define product vision, technical strategy, and multi-year roadmaps for healthcare platforms.
        • Translate complex clinical and operational workflows (patient outreach, care coordination, etc.) into scalable and reusable technical solutions.

        ---

        Feed postIT Recruiter8h • 🚀 Hiring: Technical Product Manager – RemoteWe are looking for an experienced Technical Product Manager with a strong healthcare background to join a dynamic team and drive the strategy, development, and delivery of healthcare technology platforms.
        """
    }

    func testSkipsLinkedInProfileChromeBeforeActualPost() {
        let blocks = parseJdBlocks(linkedInJD)
        // swiftlint:disable:next statement_position
        let firstText: String = if case let .paragraph(txt) = blocks.first { txt }
        else if case let .heading(txt) = blocks.first { txt } else { "" }
        XCTAssertFalse(
            firstText.contains("Technical Program Manager @ Meta"),
            "First block should not be user profile header, got: \(firstText.prefix(80))"
        )
    }

    func testIncludesActualJobTitleAsHeadingOrFirstContent() {
        let blocks = parseJdBlocks(linkedInJD)
        let allText = blocks.map { block -> String in
            switch block {
            case let .paragraph(txt): return txt
            case let .heading(txt): return txt
            case let .list(items): return items.joined(separator: " ")
            case .horizontalRule: return ""
            }
        }.joined(separator: " ")
        XCTAssertTrue(allText.contains("Technical Product Manager"), "job title should appear in parsed content")
    }

    func testStripsTheConcatenatedDuplicateParagraphAtTheBottom() {
        let blocks = parseJdBlocks(linkedInJD)
        let allText = blocks.compactMap { block -> String? in
            if case let .paragraph(txt) = block { return txt }
            return nil
        }.joined(separator: "\n")
        XCTAssertFalse(allText.contains("Feed postIT Recruiter"), "concatenated LinkedIn duplicate should be stripped")
    }

    func testDoesNotEndWithABareHrBlock() {
        let blocks = parseJdBlocks(linkedInJD)
        if case .horizontalRule = blocks.last {
            XCTFail("trailing hr should be removed")
        }
    }

    func testIncludesJobRequirementsAsListItems() {
        let blocks = parseJdBlocks(linkedInJD)
        let lists = blocks.compactMap { block -> [String]? in
            if case let .list(items) = block { return items }
            return nil
        }
        let allItems = lists.flatMap(\.self)
        XCTAssertTrue(allItems.contains(where: { $0.contains("years") }), "requirements list items should be present")
    }
}

// swiftlint:enable line_length
