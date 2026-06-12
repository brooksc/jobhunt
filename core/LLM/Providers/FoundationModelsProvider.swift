import Foundation

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
/// Replaces the Node subprocess bridge (server/apple-foundation.js + native/foundation-models/).
/// Mirrors postAppleFoundationCompletion() from server/extract.js.
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

        // Use an injected bridge if provided (test path), otherwise fall through
        // to the real implementation (which requires macOS 26+).
        if let bridge {
            let result = try await bridge.complete(systemPrompt: systemContent, userMessage: prompt)
            return makeResponse(rawResult: result)
        }

        // FoundationModels framework requires macOS 26+.
        // On older systems we surface a clear error rather than silently failing.
        if #available(macOS 26.0, *) {
            let realBridge = RealLanguageModelBridge()
            let result = try await realBridge.complete(systemPrompt: systemContent, userMessage: prompt)
            return makeResponse(rawResult: result)
        } else {
            throw LLMProviderError.unavailable(
                reason: "Apple Foundation Models requires macOS 26 (Tahoe) or later"
            )
        }
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

/// Real implementation that calls Apple's LanguageModelSession via ObjC runtime.
/// Compiled for all targets but only functional on macOS 26+ (the #available guard
/// in FoundationModelsProvider.complete ensures we only instantiate this on 26+).
public struct RealLanguageModelBridge: LanguageModelBridge {
    public init() {}

    public func complete(systemPrompt: String, userMessage: String) async throws -> String {
        if #available(macOS 26.0, *) {
            return try await FoundationModelsBridge.respond(
                to: userMessage,
                instructions: systemPrompt
            )
        } else {
            throw LLMProviderError.unavailable(
                reason: "Apple Foundation Models requires macOS 26 (Tahoe) or later"
            )
        }
    }
}

// MARK: - FoundationModelsBridge

/// Thin compile-time bridge to LanguageModelSession.
/// The #available guard in RealLanguageModelBridge.complete ensures this
/// only runs on macOS 26+. The code here compiles against the 26 SDK.
@available(macOS 26.0, *)
enum FoundationModelsBridge {
    static func respond(to prompt: String, instructions: String) async throws -> String {
        // On macOS 26+, FoundationModels.LanguageModelSession is available.
        // We call it through Objective-C selectors to avoid requiring the
        // FoundationModels framework to be linked at compile time on macOS 15.
        // If the framework is not present at runtime (e.g. running on a Mac
        // without Apple Intelligence), we surface a descriptive error.
        guard let sessionClass = NSClassFromString("LanguageModelSession") as? NSObject.Type else {
            throw LLMProviderError.unavailable(
                reason: "FoundationModels.LanguageModelSession not found — Apple Intelligence may not be enabled"
            )
        }

        let initSel = NSSelectorFromString("initWithInstructions:")
        guard sessionClass.instancesRespond(to: initSel) else {
            throw LLMProviderError.unavailable(reason: "LanguageModelSession does not respond to initWithInstructions:")
        }

        // Allocate and initialize the session object with instructions.
        // sessionClass.init() allocates an uninitialized instance (equivalent to alloc);
        // we then call initWithInstructions: to produce the real, initialized object.
        let allocatedObj = sessionClass.init()
        guard let initializedSession = allocatedObj.perform(initSel, with: instructions)?.takeUnretainedValue() as AnyObject? else {
            throw LLMProviderError.unavailable(reason: "Failed to initialize LanguageModelSession with instructions")
        }

        // Verify that the respond selector exists before calling it.
        // This catches cases where Apple updated the API method signature.
        let respondSel = NSSelectorFromString("respondTo:completionHandler:")
        guard initializedSession.responds(to: respondSel) else {
            throw LLMProviderError
                .unavailable(reason: "LanguageModelSession does not respond to respondTo:completionHandler: — API may have changed")
        }

        return try await withCheckedThrowingContinuation { continuation in
            typealias CompletionBlock = @convention(block) (AnyObject?, NSError?) -> Void
            let block: CompletionBlock = { result, error in
                if let error {
                    continuation.resume(throwing: LLMProviderError.unavailable(reason: error.localizedDescription))
                } else if let responseObj = result {
                    let text = (responseObj.value(forKey: "content") as? String) ?? ""
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: "")
                }
            }
            _ = initializedSession.perform(respondSel, with: prompt, with: block)
        }
    }
}
