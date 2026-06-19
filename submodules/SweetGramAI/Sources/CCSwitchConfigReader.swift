import Foundation

/// CC Switch compatible profile (legacy `~/.ccswitch/ccs.json` and modern provider exports).
public struct CCSwitchProfile: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var apiFormat: LLMAPIFormat

    public init(
        id: String,
        name: String,
        baseURL: String,
        apiKey: String,
        model: String,
        apiFormat: LLMAPIFormat = .openAICompletions
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.apiFormat = apiFormat
    }

    enum CodingKeys: String, CodingKey {
        case id, name, model
        case baseURL = "base_url"
        case apiKey = "api_key"
        case apiFormat = "api_format"
    }
}

public enum LLMAPIFormat: String, Codable, CaseIterable {
    case anthropicMessages = "anthropic-messages"
    case openAICompletions = "openai-completions"
}

/// Root document for imported CC Switch config (`ccs.json` or exported provider bundle).
public struct CCSwitchDocument: Codable {
    public var defaultProfileId: String?
    public var profiles: [CCSwitchProfile]
    public var proxyBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case defaultProfileId = "default"
        case profiles
        case proxyBaseURL = "proxy_base_url"
    }
}

public enum CCSwitchConfigReader {
    private static let importFileName = "ccswitch-import.json"
    private static let claudeSettingsFileName = "claude-settings-import.json"

    public static func loadProfiles() -> [CCSwitchProfile] {
        if let imported = loadDocument(from: documentsURL(appending: importFileName)) {
            return imported.profiles
        }
        if let legacy = loadLegacyCCS(from: documentsURL(appending: "ccs.json")) {
            return legacy
        }
        if let claude = loadClaudeSettings(from: documentsURL(appending: claudeSettingsFileName)) {
            return claude
        }
        return bundledFallbackProfiles()
    }

    public static func defaultProfile() -> CCSwitchProfile? {
        if let manual = LLMProfileManager.shared.activeProfile() {
            return manual
        }
        if let imported = loadDocument(from: documentsURL(appending: importFileName)),
           let id = imported.defaultProfileId,
           let profile = imported.profiles.first(where: { $0.id == id }) {
            return profile
        }
        return loadProfiles().first
    }

    // MARK: - Parsers

    private static func loadDocument(from url: URL) -> CCSwitchDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CCSwitchDocument.self, from: data)
    }

    /// Legacy `~/.ccswitch/ccs.json` format.
    private static func loadLegacyCCS(from url: URL) -> [CCSwitchProfile]? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [String: [String: String]] else {
            return nil
        }

        let descriptions = root["descriptions"] as? [String: String] ?? [:]
        return profiles.map { key, env in
            CCSwitchProfile(
                id: key,
                name: descriptions[key] ?? key,
                baseURL: env["ANTHROPIC_BASE_URL"] ?? env["OPENAI_BASE_URL"] ?? "https://api.anthropic.com",
                apiKey: env["ANTHROPIC_API_KEY"] ?? env["ANTHROPIC_AUTH_TOKEN"] ?? env["OPENAI_API_KEY"] ?? "",
                model: env["ANTHROPIC_MODEL"] ?? env["OPENAI_MODEL"] ?? "claude-sonnet-4-6",
                apiFormat: env["ANTHROPIC_BASE_URL"] != nil ? .anthropicMessages : .openAICompletions
            )
        }
    }

    /// `~/.claude/settings.json` env block.
    private static func loadClaudeSettings(from url: URL) -> [CCSwitchProfile]? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = root["env"] as? [String: String] else {
            return nil
        }

        let profile = CCSwitchProfile(
            id: "claude-settings",
            name: "Claude Settings",
            baseURL: env["ANTHROPIC_BASE_URL"] ?? "https://api.anthropic.com",
            apiKey: env["ANTHROPIC_API_KEY"] ?? env["ANTHROPIC_AUTH_TOKEN"] ?? "",
            model: env["ANTHROPIC_MODEL"] ?? "claude-sonnet-4-6",
            apiFormat: .anthropicMessages
        )
        return profile.apiKey.isEmpty ? nil : [profile]
    }

    /// Modern CC Switch provider export (`models.providers` shape).
    public static func parseModernProviderExport(data: Data) -> [CCSwitchProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let models = root["models"] as? [String: Any],
           let providers = models["providers"] as? [String: [String: Any]] {
            return providers.compactMap { id, provider in
                guard let baseURL = provider["baseUrl"] as? String,
                      let apiKey = provider["apiKey"] as? String else {
                    return nil
                }
                let api = provider["api"] as? String ?? "openai-completions"
                let modelList = provider["models"] as? [[String: Any]] ?? []
                let modelId = modelList.first?["id"] as? String ?? "gpt-4"
                return CCSwitchProfile(
                    id: id,
                    name: id,
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: modelId,
                    apiFormat: api.contains("anthropic") ? .anthropicMessages : .openAICompletions
                )
            }
        }

        return []
    }

    private static func bundledFallbackProfiles() -> [CCSwitchProfile] {
        // Empty by default — user must import CC Switch config or set via in-app UI.
        []
    }

    private static func documentsURL(appending component: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("sweetgram").appendingPathComponent(component)
    }
}
