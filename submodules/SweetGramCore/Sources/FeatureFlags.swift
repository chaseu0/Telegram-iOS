import Foundation

public struct SweetGramFeatureFlags: Codable, Equatable {
    public let aiEnabled: Bool
    public let aiChatSummary: Bool
    public let aiLlmSettings: Bool
    public let keywordMonitor: Bool
    public let barkNotifications: Bool
    public let agentServer: Bool

    enum CodingKeys: String, CodingKey {
        case aiEnabled = "ai_enabled"
        case aiChatSummary = "ai_chat_summary"
        case aiLlmSettings = "ai_llm_settings"
        case keywordMonitor = "keyword_monitor"
        case barkNotifications = "bark_notifications"
        case agentServer = "agent_server"
    }

    public static let original = SweetGramFeatureFlags(
        aiEnabled: false,
        aiChatSummary: false,
        aiLlmSettings: false,
        keywordMonitor: false,
        barkNotifications: false,
        agentServer: false
    )

    public static let aiBasic = SweetGramFeatureFlags(
        aiEnabled: true,
        aiChatSummary: true,
        aiLlmSettings: true,
        keywordMonitor: false,
        barkNotifications: false,
        agentServer: false
    )

    public static let aiFull = SweetGramFeatureFlags(
        aiEnabled: true,
        aiChatSummary: true,
        aiLlmSettings: true,
        keywordMonitor: true,
        barkNotifications: true,
        agentServer: true
    )
}

public struct SweetGramVariantConfig: Codable {
    public let variant: String
    public let displayName: String
    public let displayNameZh: String
    public let bundleId: String
    public let appSpecificUrlScheme: String
    public let features: SweetGramFeatureFlags
    public let sgConfig: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case variant
        case displayName = "display_name"
        case displayNameZh = "display_name_zh"
        case bundleId = "bundle_id"
        case appSpecificUrlScheme = "app_specific_url_scheme"
        case features
        case sgConfig = "sg_config"
    }
}

public enum SweetGramVariant: String {
    case original
    case aiBasic = "ai-basic"
    case aiFull = "ai-full"

    public var featureFlags: SweetGramFeatureFlags {
        switch self {
        case .original: return .original
        case .aiBasic: return .aiBasic
        case .aiFull: return .aiFull
        }
    }
}

public final class SweetGramBootstrap {
    public static let shared = SweetGramBootstrap()

    public private(set) var variant: SweetGramVariant = .original
    public private(set) var featureFlags: SweetGramFeatureFlags = .original
    public private(set) var bundleId: String = "com.sweetgram.original"
    public private(set) var displayName: String = "SweetGram"

    private init() {}

    public func configure(variant: SweetGramVariant, bundleId: String, displayName: String) {
        self.variant = variant
        self.featureFlags = variant.featureFlags
        self.bundleId = bundleId
        self.displayName = displayName
    }
}

/// Lightweight AnyCodable for sg_config passthrough.
public struct AnyCodable: Codable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
