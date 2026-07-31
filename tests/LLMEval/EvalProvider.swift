import Foundation
@testable import JobhuntCore

/// Builds the provider an eval runs against, from the environment.
///
/// The harness used to construct `LMStudioProvider` directly, which meant it could only evaluate a
/// local model — not the hosted one that actually produces the user's scores, and not a candidate
/// model being considered as a replacement. Every prompt change was therefore judged either by
/// eyeballing production re-scores or not at all.
///
///     JOBHUNT_EVAL_PROVIDER=openrouter \
///     JOBHUNT_EVAL_MODEL=deepseek/deepseek-v4-flash-0731 \
///     JOBHUNT_EVAL_API_KEY=sk-or-... \
///       xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
///
/// The legacy `JOBHUNT_LLM_URL` / `JOBHUNT_LLM_MODEL` pair still selects LM Studio, so existing
/// invocations keep working.
enum EvalProvider {
    struct Config {
        let provider: String
        let model: String
        let apiKey: String
        let baseURL: String
    }

    /// Env var, else a dotfile in the HOME directory.
    ///
    /// The dotfile isn't a convenience — `xcodebuild` does not forward the shell environment to the
    /// test process, so an exported variable never arrives. That's why the original harness read
    /// files, and it's the path that actually works. Home rather than the repo also means an API key
    /// can't be committed by accident.
    private static func value(env: String, file: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty { return value }
        // Xcode forwards variables prefixed with TEST_RUNNER_ to the test process.
        if let value = ProcessInfo.processInfo.environment["TEST_RUNNER_" + env], !value.isEmpty {
            return value
        }
        let path = URL.homeDirectory.appending(path: file)
        guard let contents = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func resolveConfig() -> Config? {
        let legacyURL = value(env: "JOBHUNT_LLM_URL", file: ".jobhunt-lmstudio-url")
        let provider = (value(env: "JOBHUNT_EVAL_PROVIDER", file: ".jobhunt-eval-provider")
            ?? (legacyURL != nil ? "lmstudio" : "")).lowercased()
        guard !provider.isEmpty else { return nil }
        let model = value(env: "JOBHUNT_EVAL_MODEL", file: ".jobhunt-eval-model")
            ?? value(env: "JOBHUNT_LLM_MODEL", file: ".jobhunt-lmstudio-model") ?? ""
        guard !model.isEmpty else { return nil }
        return Config(
            provider: provider,
            model: model,
            apiKey: value(env: "JOBHUNT_EVAL_API_KEY", file: ".jobhunt-eval-api-key") ?? "",
            baseURL: value(env: "JOBHUNT_EVAL_BASE_URL", file: ".jobhunt-eval-base-url") ?? legacyURL ?? ""
        )
    }

    /// The reason a provider couldn't be built, so a skipped eval says what's missing rather than
    /// silently passing.
    static func make(_ config: Config) -> (provider: (any LLMProvider)?, reason: String?) {
        func requireKey() -> String? {
            config.apiKey.isEmpty ? nil : config.apiKey
        }
        switch config.provider {
        case "lmstudio":
            guard !config.baseURL.isEmpty else {
                return (nil, "lmstudio needs JOBHUNT_EVAL_BASE_URL (or JOBHUNT_LLM_URL)")
            }
            return (LMStudioProvider(baseURL: config.baseURL, model: config.model), nil)
        case "openrouter":
            guard let key = requireKey() else { return (nil, "openrouter needs JOBHUNT_EVAL_API_KEY") }
            // Rotation off: an eval must exercise the model named, not whatever the free pool offers.
            return (OpenRouterProvider(apiKey: key, model: config.model, pool: nil), nil)
        case "google":
            guard let key = requireKey() else { return (nil, "google needs JOBHUNT_EVAL_API_KEY") }
            return (GoogleProvider(apiKey: key, model: config.model), nil)
        case "anthropic":
            guard let key = requireKey() else { return (nil, "anthropic needs JOBHUNT_EVAL_API_KEY") }
            return (AnthropicProvider(apiKey: key, model: config.model), nil)
        case "openai":
            guard let key = requireKey() else { return (nil, "openai needs JOBHUNT_EVAL_API_KEY") }
            return (OpenAIProvider(apiKey: key, model: config.model), nil)
        default:
            return (
                nil,
                "unknown provider '\(config.provider)' — use lmstudio, openrouter, google, anthropic or openai"
            )
        }
    }
}
