import Foundation

/// Whether a job meets the user's location/remote criteria — Electron parity with
/// `applyLocationFilter` (TASK-464). Pure; computed post-extraction from the extracted remote mode +
/// location against the user's preferred locations and allow-remote/hybrid/onsite settings.
public enum LocationCriteria {
    public static func meets(
        remoteType: RemoteType?,
        location: String?,
        preferredLocations: String?,
        // Where the user may work remotely. Empty/nil keeps the previous behaviour: fall back to
        // `preferredLocations` plus the built-in US tokens.
        remoteEligibilityRegions: String? = nil,
        allowRemote: Bool,
        allowHybrid: Bool,
        allowOnsite: Bool,
        filterEnabled: Bool
    ) -> Bool {
        guard filterEnabled else { return true }

        let terms = parsePreferredLocations(preferredLocations)
        let hasMatch = terms.contains { termMatches(location ?? "", term: $0) }

        // No specific preferred locations → gate on the remote mode only (unknown/none ≈ onsite),
        // except that an explicit remote-eligibility region still applies to remote roles: it is the
        // whole point of the setting that it works without naming any commuting preference.
        if terms.isEmpty {
            switch remoteType {
            case .remote:
                guard allowRemote else { return false }
                let explicit = parsePreferredLocations(remoteEligibilityRegions)
                guard !explicit.isEmpty else { return true }
                return RemoteGeography.classify(
                    location: location, preferredTerms: explicit, explicitRegions: true
                ) != .outOfBounds
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
            let explicit = parsePreferredLocations(remoteEligibilityRegions)
            return RemoteGeography.classify(
                location: location,
                preferredTerms: explicit.isEmpty ? terms : explicit,
                explicitRegions: !explicit.isEmpty
            ) != .outOfBounds
        case .hybrid: return allowHybrid && hasMatch
        case .onsite: return allowOnsite && hasMatch
        case .unknown, .none: return allowOnsite && hasMatch
        }
    }
}
