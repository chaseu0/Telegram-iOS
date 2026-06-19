import Foundation
import SweetGramCore

/// Manages OpenAI-compatible LLM profiles; API keys live in Keychain only.
public final class LLMProfileManager {
    public static let shared = LLMProfileManager()

    private let profilesKey = "sweetgram.llm.profiles"
    private let activeProfileKey = "sweetgram.llm.active_profile"

    private init() {}

    public struct StoredProfile: Codable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var baseURL: String
        public var model: String
        public var apiFormat: LLMAPIFormat

        public init(
            id: String = UUID().uuidString,
            name: String,
            baseURL: String,
            model: String,
            apiFormat: LLMAPIFormat = .openAICompletions
        ) {
            self.id = id
            self.name = name
            self.baseURL = baseURL
            self.model = model
            self.apiFormat = apiFormat
        }

        enum CodingKeys: String, CodingKey {
            case id, name, model
            case baseURL = "base_url"
            case apiFormat = "api_format"
        }

        public func toCCSwitchProfile(apiKey: String) -> CCSwitchProfile {
            CCSwitchProfile(
                id: id,
                name: name,
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                apiFormat: apiFormat
            )
        }
    }

    public func listProfiles() -> [StoredProfile] {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([StoredProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    public func activeProfileId() -> String? {
        UserDefaults.standard.string(forKey: activeProfileKey) ?? listProfiles().first?.id
    }

    public func activeProfile() -> CCSwitchProfile? {
        guard let id = activeProfileId() else { return CCSwitchConfigReader.defaultProfile() }
        return profileAsCCSwitch(id: id)
    }

    public func profileAsCCSwitch(id: String) -> CCSwitchProfile? {
        guard let stored = listProfiles().first(where: { $0.id == id }) else { return nil }
        let apiKey = KeychainStorage.get(KeychainStorage.apiKeyKeychainId(for: id)) ?? ""
        return stored.toCCSwitchProfile(apiKey: apiKey)
    }

    public func selectProfile(id: String) {
        UserDefaults.standard.set(id, forKey: activeProfileKey)
        var settings = SweetGramUserSettings.load()
        settings.selectedLLMProfileId = id
        if let model = listProfiles().first(where: { $0.id == id })?.model {
            settings.selectedModelId = model
        }
        settings.save()
    }

    @discardableResult
    public func upsertProfile(
        id: String?,
        name: String,
        baseURL: String,
        model: String,
        apiKey: String,
        apiFormat: LLMAPIFormat = .openAICompletions
    ) -> StoredProfile {
        var profiles = listProfiles()
        let profileId = id ?? UUID().uuidString
        let stored = StoredProfile(id: profileId, name: name, baseURL: baseURL, model: model, apiFormat: apiFormat)

        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index] = stored
        } else {
            profiles.append(stored)
        }

        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if !apiKey.isEmpty {
            _ = KeychainStorage.set(apiKey, forKey: KeychainStorage.apiKeyKeychainId(for: profileId))
        }
        if activeProfileId() == nil {
            selectProfile(id: profileId)
        }
        return stored
    }

    public func deleteProfile(id: String) {
        var profiles = listProfiles()
        profiles.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        KeychainStorage.delete(KeychainStorage.apiKeyKeychainId(for: id))
        if activeProfileId() == id {
            UserDefaults.standard.removeObject(forKey: activeProfileKey)
        }
    }

    public func maskedApiKey(for profileId: String) -> String {
        guard let key = KeychainStorage.get(KeychainStorage.apiKeyKeychainId(for: profileId)), !key.isEmpty else {
            return "(not set)"
        }
        if key.count <= 8 { return "••••" }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }
}
