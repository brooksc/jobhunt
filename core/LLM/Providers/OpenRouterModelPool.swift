import Foundation

/// Free structured-output model pool for OpenRouter rotation (TASK-462). Which free models exist
/// and which support structured output both change under us, so the pool is discovered from the
/// API rather than hard-coded — a pinned list goes stale silently and every extraction fails on a
/// model that no longer exists. Fetches `/models`, filters to FREE models
/// that advertise structured-output support, caches the list with a 1h TTL, and hands out models
/// round-robin for failover. A `.shared` instance persists the cache + rotation index across the
/// per-drain provider rebuilds; tests construct their own instance with an injected session.
public actor OpenRouterModelPool {
    public static let shared = OpenRouterModelPool()

    private let ttl: TimeInterval
    private var cached: [String] = []
    private var fetchedAt: Date?
    private var rotationIndex = 0

    public init(ttl: TimeInterval = 3600) {
        self.ttl = ttl
    }

    // MARK: - Pure filter (unit-tested against a captured /models fixture)

    public struct Model: Decodable {
        public let id: String
        public let pricing: Pricing?
        public let supportedParameters: [String]?
        public let architecture: Architecture?

        public struct Pricing: Decodable { public let prompt: String?; public let completion: String? }
        public struct Architecture: Decodable { public let modality: String? }

        enum CodingKeys: String, CodingKey {
            case id, pricing, architecture
            case supportedParameters = "supported_parameters"
        }
    }

    public struct ModelsResponse: Decodable { public let data: [Model] }

    /// Free (prompt & completion price 0) AND structured-output capable AND text-capable.
    public static func filterFreeStructured(_ models: [Model]) -> [String] {
        models.filter { model in
            let promptFree = (Double(model.pricing?.prompt ?? "1") ?? 1) == 0
            let completionFree = (Double(model.pricing?.completion ?? "1") ?? 1) == 0
            let params = Set(model.supportedParameters ?? [])
            let structured = params.contains("structured_outputs") || params.contains("response_format")
            // Default to text-capable when modality is absent (older shape).
            let textCapable = model.architecture?.modality.map { $0.localizedCaseInsensitiveContains("text") } ?? true
            return promptFree && completionFree && structured && textCapable
        }.map(\.id)
    }

    // MARK: - Fetch + cache

    /// The cached free-structured model ids, refetching when the TTL has elapsed. On a fetch failure
    /// the previous (possibly empty) cache is retained.
    public func models(apiKey: String, session: URLSession, now: Date = Date()) async -> [String] {
        if let fetchedAt, now.timeIntervalSince(fetchedAt) < ttl, !cached.isEmpty {
            return cached
        }
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return cached }
        var request = URLRequest(url: url)
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, _) = try await session.data(for: request)
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            let filtered = Self.filterFreeStructured(decoded.data)
            if !filtered.isEmpty {
                cached = filtered
                fetchedAt = now
                rotationIndex = 0
            }
        } catch {
            // Keep the stale cache; the provider falls back to its configured model when empty.
        }
        return cached
    }

    /// Up to `count` distinct models starting at the advancing rotation index (advances one per call).
    public func nextModels(count: Int, apiKey: String, session: URLSession, now: Date = Date()) async -> [String] {
        let models = await models(apiKey: apiKey, session: session, now: now)
        guard !models.isEmpty else { return [] }
        let start = rotationIndex % models.count
        rotationIndex = (rotationIndex + 1) % models.count
        let take = min(count, models.count)
        return (0 ..< take).map { models[(start + $0) % models.count] }
    }
}
