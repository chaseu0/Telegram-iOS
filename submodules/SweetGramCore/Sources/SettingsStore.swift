import Foundation

public struct SweetGramUserSettings: Codable {
    public var keywordMonitor: KeywordMonitorConfig
    public var selectedLLMProfileId: String?
    public var selectedModelId: String?
    public var agentServerPort: Int
    public var agentServerEnabled: Bool

    public init(
        keywordMonitor: KeywordMonitorConfig = KeywordMonitorConfig(),
        selectedLLMProfileId: String? = nil,
        selectedModelId: String? = nil,
        agentServerPort: Int = 8787,
        agentServerEnabled: Bool = true
    ) {
        self.keywordMonitor = keywordMonitor
        self.selectedLLMProfileId = selectedLLMProfileId
        self.selectedModelId = selectedModelId
        self.agentServerPort = agentServerPort
        self.agentServerEnabled = agentServerEnabled
    }

    enum CodingKeys: String, CodingKey {
        case keywordMonitor = "keyword_monitor"
        case selectedLLMProfileId = "selected_llm_profile_id"
        case selectedModelId = "selected_model_id"
        case agentServerPort = "agent_server_port"
        case agentServerEnabled = "agent_server_enabled"
    }

    public static func load() -> SweetGramUserSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(SweetGramUserSettings.self, from: data) else {
            return SweetGramUserSettings()
        }
        return settings
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static let storageKey = "sweetgram.user.settings"
}

public enum SweetGramSettingsStore {
    public static func applyPersistedSettings() {
        let settings = SweetGramUserSettings.load()
        if SweetGramBootstrap.shared.featureFlags.keywordMonitor {
            KeywordMonitor.shared.updateConfig(settings.keywordMonitor)
        }
    }
}
