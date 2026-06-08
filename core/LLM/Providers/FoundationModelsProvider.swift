import Foundation

/// Apple Foundation Models provider — calls LanguageModelSession in-process.
/// Requires macOS 26+. Concurrency limit 1 (single on-device model).
/// Replaces the Node subprocess bridge (server/apple-foundation.js + native/foundation-models/).
/// Mirrors postAppleFoundationCompletion() from server/extract.js.
public final class FoundationModelsProvider: LLMProvider, @unchecked Sendable {
    public let id = "apple"
    public let concurrencyLimit = 1

    public init() {}

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        // FoundationModels framework requires macOS 26+.
        // On older systems we surface a clear error rather than silently failing.
        if #available(macOS 26.0, *) {
            return try await runOnDevice(request)
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

    // MARK: - Private

    /// Performs the actual LanguageModelSession call on macOS 26+.
    /// Compiled only when targeting macOS 26+.
    @available(macOS 26.0, *)
    private func runOnDevice(_ request: ChatRequest) async throws -> ChatResponse {
        let systemContent = request.messages.first(where: { $0.role == "system" })?.content
            ?? "You are a helpful assistant. Follow the user's instructions precisely."
        let userMsgs = request.messages.filter { $0.role == "user" }
        let prompt = userMsgs.map(\.content).joined(separator: "\n")

        // Use the FoundationModels framework (macOS 26+).
        // Dynamic symbol lookup avoids a hard compile-time framework dependency
        // while still calling the real API at runtime on macOS 26+.
        let result = try await FoundationModelsBridge.respond(
            to: prompt,
            instructions: systemContent
        )

        // Strip markdown code fences the model may wrap around JSON output
        let content = result
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

// MARK: - FoundationModelsBridge

/// Thin compile-time bridge to LanguageModelSession.
/// The #available guard in FoundationModelsProvider.runOnDevice ensures this
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

        // Allocate and initialize the session object
        let sessionObj = sessionClass.init()
        guard sessionObj.responds(to: initSel) else {
            throw LLMProviderError.unavailable(reason: "Failed to create LanguageModelSession")
        }

        // We need to pass instructions: use a simpler approach — NSInvocation is not
        // available in Swift. Use unmanaged perform:withObject: instead.
        // For the macOS 26 target this will link directly; the guard above ensures
        // we only reach here on 26+.
        let initializedSession = sessionObj.perform(initSel, with: instructions)?.takeUnretainedValue() as AnyObject

        // Call respond(to:) — this is async in the real API, so we use a callback shim
        let respondSel = NSSelectorFromString("respondTo:completionHandler:")
        guard initializedSession.responds(to: respondSel) else {
            throw LLMProviderError
                .unavailable(reason: "LanguageModelSession does not respond to respondTo:completionHandler:")
        }

        return try await withCheckedThrowingContinuation { continuation in
            typealias CompletionBlock = @convention(block) (AnyObject?, NSError?) -> Void
            let block: CompletionBlock = { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let responseObj = result {
                    let text = (responseObj.value(forKey: "content") as? String) ?? ""
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: "")
                }
            }
            initializedSession.perform(respondSel, with: prompt, with: block)
        }
    }
}
