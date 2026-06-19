import Foundation
import SweetGramCore

/// Settings data provider for LLM profile/model selection (ItemListUI integration point).
/// UIKit-dependent presentation methods moved to SweetGramUIHooks.
public final class LLMSettingsPresenter: NSObject {
    public static let shared = LLMSettingsPresenter()

    private override init() {
        super.init()
        reload()
    }

    public func reload() {
        let settings = SweetGramUserSettings.load()
        if let id = settings.selectedLLMProfileId {
            LLMProfileManager.shared.selectProfile(id: id)
        }
    }

    public var isAvailable: Bool {
        SweetGramBootstrap.shared.featureFlags.aiLlmSettings
    }

    public func profileRows() -> [(id: String, title: String, subtitle: String)] {
        var rows = LLMProfileManager.shared.listProfiles().map { profile in
            (
                id: profile.id,
                title: profile.name,
                subtitle: "\(profile.model) · \(profile.baseURL) · \(LLMProfileManager.shared.maskedApiKey(for: profile.id))"
            )
        }

        for row in CCSwitchConfigReader.loadProfiles().map({ profile in
            (id: "ccswitch:\(profile.id)", title: profile.name, subtitle: "\(profile.model) · \(profile.baseURL) · CC Switch")
        }) {
            if !rows.contains(where: { $0.id == row.id }) {
                rows.append(row)
            }
        }
        return rows
    }

    public func selectProfile(id: String) {
        if id.hasPrefix("ccswitch:") {
            let rawId = String(id.dropFirst("ccswitch:".count))
            var settings = SweetGramUserSettings.load()
            settings.selectedLLMProfileId = id
            if let profile = CCSwitchConfigReader.loadProfiles().first(where: { $0.id == rawId }) {
                settings.selectedModelId = profile.model
            }
            settings.save()
            return
        }
        LLMProfileManager.shared.selectProfile(id: id)
    }

    public func activeProfile() -> CCSwitchProfile? {
        let settings = SweetGramUserSettings.load()
        if let id = settings.selectedLLMProfileId, id.hasPrefix("ccswitch:") {
            let rawId = String(id.dropFirst("ccswitch:".count))
            return CCSwitchConfigReader.loadProfiles().first(where: { $0.id == rawId })
        }
        return LLMProfileManager.shared.activeProfile() ?? CCSwitchConfigReader.defaultProfile()
    }

    public func importCCSwitchJSON(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported: [CCSwitchProfile]

        if let doc = try? JSONDecoder().decode(CCSwitchDocument.self, from: data) {
            imported = doc.profiles
        } else {
            imported = CCSwitchConfigReader.parseModernProviderExport(data: data)
        }

        guard !imported.isEmpty else {
            throw LLMSettingsError.invalidImport
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("sweetgram", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("ccswitch-import.json"))
        reload()
    }

    public func saveManualProfile(
        id: String?,
        name: String,
        baseURL: String,
        model: String,
        apiKey: String
    ) {
        let profile = LLMProfileManager.shared.upsertProfile(
            id: id,
            name: name,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey
        )
        LLMProfileManager.shared.selectProfile(id: profile.id)
    }

    /// Returns (title, message) for connectivity test. Caller presents UI.
    public func testConnectivity(completion: @escaping (String, String) -> Void) {
        guard let profile = activeProfile() else {
            completion("LLM 连接失败", "No profile configured. Add base URL, API key, and model.")
            return
        }

        let request = LLMCompletionRequest(
            messages: [LLMMessage(role: "user", content: "Reply with exactly: SweetGram OK")],
            model: profile.model,
            maxTokens: 16,
            temperature: 0
        )

        LLMClient.shared.complete(request: request, profile: profile) { result in
            switch result {
            case let .success(response):
                completion("LLM 连接成功", response.text)
            case let .failure(error):
                completion("LLM 连接失败", error.localizedDescription)
            }
        }
    }
}

public enum LLMSettingsError: LocalizedError {
    case invalidImport

    public var errorDescription: String? {
        switch self {
        case .invalidImport: return "Unable to parse CC Switch configuration file"
        }
    }
}
