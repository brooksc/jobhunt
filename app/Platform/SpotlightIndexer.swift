import CoreSpotlight
import Foundation
import JobhuntCore

/// Publishes jobs to Spotlight (TASK-590).
///
/// Thin by design: what to index is decided by `SpotlightEntry` in Core, where it's unit-tested.
/// This only translates those values into `CSSearchableItem` and talks to the framework, which can't
/// be exercised in a unit test.
///
/// Every failure is swallowed to a log. Spotlight is a convenience; a user whose index is broken
/// should still have a working app, and there is nothing they could do about a `CSSearchableIndex`
/// error anyway.
@MainActor
public enum SpotlightIndexer {
    /// Domain for the app's items, so a clear can be scoped rather than global.
    static let domainIdentifier = "com.jobhunt-app.jobhunt.jobs"

    public static func index(_ entries: [SpotlightEntry]) {
        guard !entries.isEmpty else { return }
        let items = entries.map { entry -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = entry.title
            attributes.contentDescription = entry.contentDescription
            attributes.keywords = entry.keywords
            attributes.contentURL = URL(string: entry.deepLink)
            return CSSearchableItem(
                uniqueIdentifier: entry.uniqueIdentifier,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                NSLog("SpotlightIndexer: index failed: \(error)")
            }
        }
    }

    /// Replace the app's whole Spotlight domain with `entries`.
    ///
    /// `index` alone only ever *adds*: a job deleted through a path that doesn't call `remove`
    /// (the MCP tools, the migrator, a bulk operation) kept its Spotlight hit indefinitely, and the
    /// hit opens the app and lands on nothing. Clearing the domain first makes the launch pass
    /// authoritative — whatever the store holds now is exactly what Spotlight holds.
    ///
    /// Clear-then-index, not a diff: the corpus is a few hundred rows, re-indexing is cheap, and a
    /// diff would need its own record of what was published last time.
    public static func replaceAll(_ entries: [SpotlightEntry]) {
        clearAll { _ in
            Task { @MainActor in index(entries) }
        }
    }

    /// #3 — a deleted job must stop appearing. A stale Spotlight hit that opens the app and finds
    /// nothing is worse than no hit at all.
    public static func remove(jobNumbers: [Int]) {
        guard !jobNumbers.isEmpty else { return }
        let ids = jobNumbers.map { SpotlightEntry.identifier(jobNumber: $0) }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { error in
            if let error {
                NSLog("SpotlightIndexer: delete failed: \(error)")
            }
        }
    }

    /// #4 — clears only this app's domain, not the whole index.
    public static func clearAll(completion: (@Sendable (Error?) -> Void)? = nil) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
                if let error {
                    NSLog("SpotlightIndexer: clear failed: \(error)")
                }
                completion?(error)
            }
    }
}
