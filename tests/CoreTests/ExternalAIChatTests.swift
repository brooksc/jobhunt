import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-606: hosted-chat URL prefill + conservative size fallback.
final class ExternalAIChatTests: XCTestCase {
    func testChatGPTPrefillEncodesPrompt() throws {
        let url = try XCTUnwrap(AIChatProvider.chatGPT.prefillURL(prompt: "hello world\nline two"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://chatgpt.com/?q="))
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            comps.queryItems?.first(where: { $0.name == "q" })?.value,
            "hello world\nline two",
            "the prompt round-trips through the query item"
        )
    }

    func testClaudePrefillTargetsNewChat() throws {
        let url = try XCTUnwrap(AIChatProvider.claude.prefillURL(prompt: "hi"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://claude.ai/new?q="))
    }

    func testOversizedPromptFallsBackToNil() {
        let big = String(repeating: "x", count: ExternalAIChat.maxPrefillPromptChars + 1)
        XCTAssertNil(AIChatProvider.chatGPT.prefillURL(prompt: big), "oversized prompt must not build a prefill URL")
        XCTAssertNil(AIChatProvider.claude.prefillURL(prompt: big))
    }

    func testBlankChatURLsAreAlwaysAvailable() {
        XCTAssertEqual(AIChatProvider.chatGPT.blankChatURL.absoluteString, "https://chatgpt.com/")
        XCTAssertEqual(AIChatProvider.claude.blankChatURL.absoluteString, "https://claude.ai/new")
    }
}
