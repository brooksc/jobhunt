import Foundation

/// Parses a price a user typed, and says why it was rejected.
///
/// The fields were `Double(text)` with no else branch: a stray character meant the value was
/// silently not saved, the field kept showing what had been typed, and the cost estimate kept using
/// the old number. Nothing on screen distinguished that from a successful save.
public enum PriceInput {
    public enum Invalid: Error, Equatable, Sendable {
        case notANumber
        case negative

        public var message: String {
            switch self {
            case .notANumber: "Enter a number, like 0.25"
            case .negative: "Price can't be negative"
            }
        }
    }

    /// Returns the parsed price, or the reason it can't be used.
    ///
    /// Blank is `nil`-valid rather than an error — clearing a field is a normal thing to do while
    /// retyping, and flagging it mid-edit would put a red error under every field the user is
    /// currently working in. The caller leaves the stored price alone in that case.
    public static func parse(_ text: String) -> Result<Double?, Invalid> {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }
        // A leading "$" is what people type for a price; accepting it is cheaper than explaining it.
        if trimmed.hasPrefix("$") { trimmed.removeFirst() }
        trimmed = trimmed.trimmingCharacters(in: .whitespaces)

        guard let value = Double(trimmed), value.isFinite else { return .failure(.notANumber) }
        guard value >= 0 else { return .failure(.negative) }
        return .success(value)
    }

    /// Convenience for a view: the error to show, or nil.
    public static func validationMessage(_ text: String) -> String? {
        switch parse(text) {
        case .success: nil
        case let .failure(reason): reason.message
        }
    }
}
