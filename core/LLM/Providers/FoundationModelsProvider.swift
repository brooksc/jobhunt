import Foundation
import FoundationModels

// MARK: - LanguageModelBridge protocol

/// Abstracts the Apple FoundationModels API so callers can be tested
/// without a real model session. The real implementation lives in
/// `RealLanguageModelBridge`; tests inject a mock.
public protocol LanguageModelBridge: Sendable {
    func complete(systemPrompt: String, userMessage: String) async throws -> String
}

// MARK: - FoundationModelsProvider

/// Apple Foundation Models provider — calls LanguageModelSession in-process.
/// Requires macOS 26+. Concurrency limit 1 (single on-device model).
public final class FoundationModelsProvider: LLMProvider, @unchecked Sendable {
    public let id = "foundation_models"
    public let concurrencyLimit = 1

    private let bridge: LanguageModelBridge?

    /// - Parameter bridge: Override for testing. Pass `nil` (default) to use the
    ///   real `RealLanguageModelBridge` on macOS 26+, or surface an unavailable error.
    public init(bridge: LanguageModelBridge? = nil) {
        self.bridge = bridge
    }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let systemContent = request.messages.first(where: { $0.role == "system" })?.content
            ?? "You are a helpful assistant. Follow the user's instructions precisely."
        let userMsgs = request.messages.filter { $0.role == "user" }
        let prompt = userMsgs.map(\.content).joined(separator: "\n")

        // Tests inject a bridge to exercise the free-form text path deterministically.
        if let bridge {
            let result = try await bridge.complete(systemPrompt: systemContent, userMessage: prompt)
            return makeResponse(rawResult: result)
        }

        guard #available(macOS 26.0, *) else {
            throw LLMProviderError.unavailable(
                reason: "Apple Foundation Models requires macOS 26 (Tahoe) or later"
            )
        }
        let realBridge = RealLanguageModelBridge()

        // Preferred path: guided generation produces a constrained, typed structure that always
        // decodes — no JSON parsing/repair, no "could not be parsed as valid JSON" failures.
        if let kind = request.structuredOutput {
            do {
                let json = try await realBridge.completeStructured(
                    systemPrompt: systemContent, userMessage: prompt, kind: kind
                )
                return ChatResponse(content: json, model: "apple-foundation-models", responseFormat: .jsonObject)
            } catch {
                // Resilience: if guided generation is unavailable or fails, degrade to free-form
                // text + the engine's JSON repair rather than failing the request outright.
                let result = try await realBridge.complete(systemPrompt: systemContent, userMessage: prompt)
                return makeResponse(rawResult: result)
            }
        }

        let result = try await realBridge.complete(systemPrompt: systemContent, userMessage: prompt)
        return makeResponse(rawResult: result)
    }

    /// Returns true if Foundation Models is available on this system (macOS 26+).
    public static func isAvailable() -> Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    // MARK: - Private helpers

    private func makeResponse(rawResult: String) -> ChatResponse {
        // Strip markdown code fences the model may wrap around JSON output
        let content = rawResult
            .replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ChatResponse(
            content: content,
            model: "apple-foundation-models",
            responseFormat: .text
        )
    }
}

// MARK: - RealLanguageModelBridge

/// Calls LanguageModelSession directly via the FoundationModels API (macOS 26+).
/// The FoundationModels framework is weakly linked — absent on macOS 15, present on macOS 26+.
@available(macOS 26.0, *)
public struct RealLanguageModelBridge: LanguageModelBridge {
    public init() {}

    public func complete(systemPrompt: String, userMessage: String) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        do {
            let response = try await session.respond(to: userMessage)
            return response.content
        } catch {
            throw LLMProviderError.unavailable(reason: error.localizedDescription)
        }
    }

    /// Guided generation: constrains the model to a typed @Generable schema and serialises the
    /// result to the JSON shape ExtractionEngine expects.
    func completeStructured(
        systemPrompt: String,
        userMessage: String,
        kind: StructuredOutputKind
    ) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        let encoder = JSONEncoder()
        switch kind {
        case .jobExtraction:
            let response = try await session.respond(to: userMessage, generating: GeneratedExtraction.self)
            return try encode(response.content, with: encoder)
        case .fitScore:
            let response = try await session.respond(to: userMessage, generating: GeneratedFit.self)
            return try encode(response.content, with: encoder)
        }
    }

    private func encode(_ value: some Encodable, with encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LLMProviderError.noResponse
        }
        return json
    }
}
