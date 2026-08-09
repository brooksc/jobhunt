import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// The recommendation is named in three places — onboarding, Settings and a public help page — and the
/// point of the constant is that the first two can't drift from each other.
final class ModelRecommendationTests: XCTestCase {
    /// #4: onboarding and Settings both read these; a test that the model ID is a real OpenRouter-style
    /// slug catches the typo that would otherwise only show up as a failed API call.
    func testRecommendationIsConcrete() {
        XCTAssertEqual(ModelRecommendation.providerID, "openrouter")
        XCTAssertTrue(
            ModelRecommendation.modelID.contains("/"),
            "OpenRouter model IDs are vendor/model — got \(ModelRecommendation.modelID)"
        )
        XCTAssertTrue(ModelRecommendation.summary.contains(ModelRecommendation.modelLabel))
    }

    /// #5: "learn more" tells the reader nothing about whether clicking is worth it.
    func testLinkTextSaysWhatTheReaderGets() {
        let text = ModelRecommendation.linkText.lowercased()
        XCTAssertFalse(text.contains("learn more"))
        XCTAssertFalse(text.contains("click here"))
        XCTAssertTrue(text.contains("cost"), "the link should name what it answers: \(text)")
    }

    /// #6: MAS builds are sandboxed and have no DMG-only helper. An `https://` URL works in both; a
    /// file path or a custom scheme would work in exactly one and fail silently in the other.
    func testHelpURLIsPubliclyReachableFromASandbox() throws {
        let url = try XCTUnwrap(URL(string: ModelRecommendation.helpURL))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "jobhunt-app.com")
    }

    /// #3: one tap sets provider *and* model. The ordering matters — `applyProviderChange` resets the
    /// model to whatever was last used for that provider, so setting the model first would be undone.
    @MainActor
    func testApplyRecommendationSetsBothProviderAndModel() throws {
        let container = try ModelContainerFactory.inMemory()
        let settings = SettingsStore(modelContext: ModelContext(container))
        settings.llmProvider = "anthropic"
        settings.llmModel = "claude-haiku-4-5"

        let form = AIProviderFormModel(settings: settings, listModels: { _, _, _ in [] })
        form.applyRecommendation()

        XCTAssertEqual(settings.llmProvider, ModelRecommendation.providerID)
        XCTAssertEqual(settings.llmModel, ModelRecommendation.modelID)
        XCTAssertEqual(form.modelText, ModelRecommendation.modelID)
    }
}
