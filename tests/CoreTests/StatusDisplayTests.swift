import Foundation
import XCTest
@testable import JobhuntCore

/// The status vocabulary users see, kept separate from the stored raw values.
final class StatusDisplayTests: XCTestCase {
    /// The rename that started this: "pursuing" is displayed as "Interested", but the stored value
    /// must not change — CSV/MCP/the extension depend on it, and `statusTarget` parses it from notes.
    func testPursuingDisplaysAsInterestedButKeepsItsRawValue() {
        XCTAssertEqual(JobStatus.pursuing.displayName, "Interested")
        XCTAssertEqual(JobStatus.pursuing.rawValue, "pursuing")
    }

    func testEveryStatusHasANonRawDisplayName() {
        for status in JobStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty, status.rawValue)
        }
    }

    func testLabelForRawValueIsCaseInsensitiveAndPassesThroughUnknowns() {
        XCTAssertEqual(StatusDisplay.label(forRawValue: "pursuing"), "Interested")
        XCTAssertEqual(StatusDisplay.label(forRawValue: "PURSUING"), "Interested")
        XCTAssertEqual(StatusDisplay.label(forRawValue: "applied"), "Applied")
        // An unrecognised legacy token is shown as-is rather than blanked.
        XCTAssertEqual(StatusDisplay.label(forRawValue: "saved"), "saved")
    }

    // MARK: - Timeline notes

    /// 162 stored notes read "Status changed from new to pursuing". The user saw the raw word.
    func testStatusNoteIsTranslatedForDisplay() {
        XCTAssertEqual(
            StatusDisplay.humanizedNote("Status changed from new to pursuing"),
            "Status changed from New to Interested"
        )
        XCTAssertEqual(
            StatusDisplay.humanizedNote("Status changed from pursuing to applied"),
            "Status changed from Interested to Applied"
        )
    }

    func testRestoredNoteIsTranslated() {
        XCTAssertEqual(
            StatusDisplay.humanizedNote("Restored to pursuing — un-marked a heuristic duplicate flag"),
            "Restored to Interested — un-marked a heuristic duplicate flag"
        )
    }

    /// Translation is display-only; nothing may rewrite what's persisted, because
    /// `DashboardMetrics.statusTarget` parses the raw token out of the stored text.
    func testStoredNoteStillParsesToTheRawTargetAfterTranslation() {
        let stored = "Status changed from new to pursuing"
        XCTAssertEqual(DashboardMetrics.statusTarget(fromNote: stored), "pursuing")
        // The humanized form is for rendering only — it is never written back.
        XCTAssertNotEqual(StatusDisplay.humanizedNote(stored), stored)
    }

    func testUnrelatedNotesAreUntouched() {
        let note = "Followed up with Jordan about the referral."
        XCTAssertEqual(StatusDisplay.humanizedNote(note), note)
    }

    /// Only machine-written status notes are rewritten. A user's own note mentioning "new" or
    /// "applied" as ordinary words must survive untouched — otherwise their prose gets capitalized
    /// mid-sentence by a display filter they never asked for.
    func testUserProseIsNeverRewritten() {
        for note in [
            "Applied via the new portal today",
            "They said the role is closed to new candidates",
            "renewed my interest with the recruiter"
        ] {
            XCTAssertEqual(StatusDisplay.humanizedNote(note), note, note)
        }
    }

    /// Incidental status words inside a status note must survive: "duplicate" here is an English
    /// word describing the flag, not the transition target.
    func testIncidentalStatusWordsInsideStatusNotesAreNotCapitalized() {
        XCTAssertEqual(
            StatusDisplay.humanizedNote("Restored to pursuing — un-marked a heuristic duplicate flag"),
            "Restored to Interested — un-marked a heuristic duplicate flag"
        )
    }

    /// Word-boundary matching inside a genuine status note.
    func testWordBoundariesRespectedWithinStatusNotes() {
        XCTAssertEqual(
            StatusDisplay.humanizedNote("Status changed from new to expired"),
            "Status changed from New to Expired"
        )
    }

    // MARK: - Criteria vocabulary

    /// The inconsistency reported on job 327: a posting that never stated its arrangement showed
    /// "Outside criteria" on the detail while the filter classified it as "Not stated", so it read as
    /// rejected in one place and was missing from the matching filter in the other.
    ///
    /// The label is generic now that the bucket also covers a missing salary or an unscored job; the
    /// specific cause is supplied by the requirement reason shown alongside it.
    func testSilentPostingReadsAsNotStatedNotRejected() {
        let bucket = JobFilterRules.criteriaBucket(meetsCriteria: false, remoteType: .unknown)
        XCTAssertEqual(bucket, .notStated)
        XCTAssertEqual(bucket?.label, "Not stated")
    }

    func testStatedRejectionStillReadsAsOutsideCriteria() {
        XCTAssertEqual(
            JobFilterRules.criteriaBucket(meetsCriteria: false, remoteType: .onsite)?.label,
            "Outside criteria"
        )
        XCTAssertEqual(
            JobFilterRules.criteriaBucket(meetsCriteria: true, remoteType: .remote)?.label,
            "Meets criteria"
        )
    }
}
