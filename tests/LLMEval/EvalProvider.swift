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

    /// `~/.config/jobhunt/` — the XDG-style location config belongs in.
    static var configDirectory: URL {
        URL.homeDirectory.appending(path: ".config/jobhunt", directoryHint: .isDirectory)
    }

    /// Raw contents of a config file, or nil. Not trimmed — callers that hold prose (a résumé) need
    /// it verbatim.
    static func fileContents(_ name: String, legacy: String? = nil) -> String? {
        let candidates = [configDirectory.appending(path: name)]
            + (legacy.map { [URL.homeDirectory.appending(path: $0)] } ?? [])
        for path in candidates {
            if let contents = try? String(contentsOf: path, encoding: .utf8), !contents.isEmpty {
                return contents
            }
        }
        return nil
    }

    /// Env var, else `~/.config/jobhunt/<name>`, else the pre-XDG `~/.<legacy>` path.
    ///
    /// Files rather than the environment because `xcodebuild` does not forward the shell environment
    /// to the test process, so an exported variable never arrives — that's why the original harness
    /// read files. Outside the repo also means an API key can't be committed by accident.
    private static func value(env: String, file: String, legacy: String? = nil) -> String? {
        if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty { return value }
        // Xcode forwards variables prefixed with TEST_RUNNER_ to the test process.
        if let value = ProcessInfo.processInfo.environment["TEST_RUNNER_" + env], !value.isEmpty {
            return value
        }
        return fileContents(file, legacy: legacy)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    /// Every model to evaluate, in order.
    ///
    /// `eval-models` holds one `model` or `provider:model` per line, so several models can be
    /// compared in a single run against identical fixtures — the only way to tell a real difference
    /// between two models from this scorer's run-to-run variance. A single `eval-model` still works.
    static func resolveConfigs() -> [Config] {
        let legacyURL = value(env: "JOBHUNT_LLM_URL", file: "eval-base-url", legacy: ".jobhunt-lmstudio-url")
        let defaultProvider = (value(
            env: "JOBHUNT_EVAL_PROVIDER",
            file: "eval-provider",
            legacy: ".jobhunt-eval-provider"
        )
            ?? (legacyURL != nil ? "lmstudio" : "")).lowercased()
        /// Per-provider keys, because the point of a multi-model run is comparing ACROSS providers —
        /// deepseek on OpenRouter against gemini on Google needs two different keys. A single
        /// `eval-api-key` still covers the case where every model shares one provider.
        func key(for provider: String) -> String {
            value(env: "JOBHUNT_EVAL_API_KEY_" + provider.uppercased(), file: "eval-api-key-" + provider)
                ?? value(env: "JOBHUNT_EVAL_API_KEY", file: "eval-api-key", legacy: ".jobhunt-eval-api-key")
                ?? ""
        }
        let baseURL = value(
            env: "JOBHUNT_EVAL_BASE_URL",
            file: "eval-base-url",
            legacy: ".jobhunt-eval-base-url"
        ) ?? legacyURL ?? ""

        /// A "provider:model" line overrides the default provider, so models hosted in different
        /// places can be compared side by side. Split on the FIRST colon only — OpenRouter model ids
        /// contain slashes but the provider prefix is unambiguous.
        func config(from line: String) -> Config? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let known = ["lmstudio", "openrouter", "google", "anthropic", "openai"]
            if let colon = trimmed.firstIndex(of: ":") {
                let head = String(trimmed[..<colon]).lowercased()
                let tail = String(trimmed[trimmed.index(after: colon)...])
                if known.contains(head), !tail.isEmpty {
                    return Config(provider: head, model: tail, apiKey: key(for: head), baseURL: baseURL)
                }
            }
            guard !defaultProvider.isEmpty else { return nil }
            return Config(
                provider: defaultProvider, model: trimmed,
                apiKey: key(for: defaultProvider), baseURL: baseURL
            )
        }

        if let list = fileContents("eval-models") {
            let configs = list.split(separator: "\n").compactMap { config(from: String($0)) }
            if !configs.isEmpty { return configs }
        }
        let single = value(env: "JOBHUNT_EVAL_MODEL", file: "eval-model", legacy: ".jobhunt-eval-model")
            ?? value(env: "JOBHUNT_LLM_MODEL", file: "eval-model", legacy: ".jobhunt-lmstudio-model")
        return single.flatMap(config(from:)).map { [$0] } ?? []
    }

    /// Back-compat for the single-model suites.
    static func resolveConfig() -> Config? {
        resolveConfigs().first
    }

    /// The résumé evals score against: the user's real master when they've placed it at
    /// `~/.config/jobhunt/eval-resume.md`, otherwise a synthetic stand-in.
    ///
    /// Deliberately NOT committed. This repo is public, and a résumé is a full work history — real
    /// employers, dates and scope. Reading it from config keeps evals honest without publishing it.
    static func resume(fallback: String) -> (text: String, isReal: Bool) {
        guard let real = fileContents("eval-resume.md")?.trimmingCharacters(in: .whitespacesAndNewlines),
              real.count > 500
        else { return (fallback, false) }
        return (real, true)
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
            guard let key = requireKey() else {
                return (nil, "openrouter needs ~/.config/jobhunt/eval-api-key-openrouter (or eval-api-key)")
            }
            // Rotation off: an eval must exercise the model named, not whatever the free pool offers.
            return (OpenRouterProvider(apiKey: key, model: config.model, pool: nil), nil)
        case "google":
            guard let key = requireKey() else {
                return (nil, "google needs ~/.config/jobhunt/eval-api-key-google (or eval-api-key)")
            }
            return (GoogleProvider(apiKey: key, model: config.model), nil)
        case "anthropic":
            guard let key = requireKey() else {
                return (nil, "anthropic needs ~/.config/jobhunt/eval-api-key-anthropic (or eval-api-key)")
            }
            return (AnthropicProvider(apiKey: key, model: config.model), nil)
        case "openai":
            guard let key = requireKey() else {
                return (nil, "openai needs ~/.config/jobhunt/eval-api-key-openai (or eval-api-key)")
            }
            return (OpenAIProvider(apiKey: key, model: config.model), nil)
        default:
            return (
                nil,
                "unknown provider '\(config.provider)' — use lmstudio, openrouter, google, anthropic or openai"
            )
        }
    }
}
