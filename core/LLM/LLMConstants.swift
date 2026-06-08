import Foundation

/// Character-limit constants shared between the extraction prompt builder and UI truncation.
/// Values mirror the JS constants in server/extract.js.
public enum LLMConstants {
    public static let maxDescriptionChars = 32000
    public static let maxResumeChars = 12000
}
