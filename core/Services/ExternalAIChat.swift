import Foundation

// MARK: - External AI chat destinations (TASK-606)

/// Opens a prompt in a hosted AI chat via a URL query prefill. Prefill is best-effort — ChatGPT's
/// `?q=` is documented-ish, Claude's `/new?q=` is not and may change — so callers must always copy the
/// full prompt to the clipboard first and fall back to the blank chat when prefill can't be used.
public enum AIChatProvider: String, Sendable, CaseIterable {
    case chatGPT
    case claude

    public var displayName: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        }
    }

    /// The blank new-chat page — always openable; the fallback when the prompt is too big to prefill.
    public var blankChatURL: URL {
        switch self {
        case .chatGPT: URL(string: "https://chatgpt.com/")!
        case .claude: URL(string: "https://claude.ai/new")!
        }
    }

    private var prefillBase: String {
        switch self {
        case .chatGPT: "https://chatgpt.com/"
        case .claude: "https://claude.ai/new"
        }
    }

    /// A prefilled-chat URL (`…?q=<encoded prompt>`), or nil when the prompt exceeds the conservative
    /// length budget or can't be encoded — in which case the caller opens `blankChatURL` and tells the
    /// user the prompt is on the clipboard to paste.
    public func prefillURL(prompt: String) -> URL? {
        guard prompt.count <= ExternalAIChat.maxPrefillPromptChars else { return nil }
        var comps = URLComponents(string: prefillBase)
        comps?.queryItems = [URLQueryItem(name: "q", value: prompt)]
        // Guard the fully-encoded length too — query-encoding can multiply size (spaces, newlines).
        guard let url = comps?.url, url.absoluteString.count <= ExternalAIChat.maxEncodedURLChars else {
            return nil
        }
        return url
    }
}

public enum ExternalAIChat {
    /// Conservative prompt-length ceiling for URL prefill. A full resume + job description prompt is
    /// far larger than this, so those deliberately fall back to a blank chat + clipboard rather than a
    /// truncated or broken URL. Short prompts (outreach, etc.) prefill fine.
    public static let maxPrefillPromptChars = 6000
    /// Hard ceiling on the encoded URL length (browsers/servers reject very long URLs).
    public static let maxEncodedURLChars = 16000
}
