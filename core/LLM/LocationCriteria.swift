import Foundation

/// Whether a job meets the user's location/remote criteria — Electron parity with
/// `applyLocationFilter` (TASK-464). Pure; computed post-extraction from the extracted remote mode +
/// location against the user's preferred locations and allow-remote/hybrid/onsite settings.
public enum LocationCriteria {
    public static func meets(
        remoteType: RemoteType?,
        location: String?,
        preferredLocations: String?,
        allowRemote: Bool,
        allowHybrid: Bool,
        allowOnsite: Bool,
        filterEnabled: Bool
    ) -> Bool {
        guard filterEnabled else { return true }

        let terms = parsePreferredLocations(preferredLocations)
        let hasMatch = terms.contains { termMatches(location ?? "", term: $0) }

        // No specific preferred locations → gate on the remote mode only (unknown/none ≈ onsite).
        if terms.isEmpty {
            switch remoteType {
            case .remote: return allowRemote
            case .hybrid: return allowHybrid
            case .onsite: return allowOnsite
            case .unknown, .none: return allowOnsite
            }
        }

        // Preferred locations set → a remote role must still be offered somewhere the user can work
        // (only ruled out when the location positively names foreign places and nothing eligible);
        // hybrid/onsite (and unknown) also require a location match.
        switch remoteType {
        case .remote:
            guard allowRemote else { return false }
            return RemoteGeography.classify(location: location, preferredTerms: terms) != .outOfBounds
        case .hybrid: return allowHybrid && hasMatch
        case .onsite: return allowOnsite && hasMatch
        case .unknown, .none: return allowOnsite && hasMatch
        }
    }
}
