import Foundation
import BuildConfig
import AccountContext
import SweetGramIntegration
import SweetGramCore

public enum SweetGramBootstrapHook {
    private static var didBootstrap = false

    public static func bootstrapIfNeeded(context: AccountContext? = nil) {
        guard !didBootstrap else {
            if let context {
                attachAgentIfNeeded(context: context)
            }
            return
        }
        didBootstrap = true

        let bundleId = Bundle.main.bundleIdentifier ?? "com.sweetgram.original"
        let buildConfig = BuildConfig(baseAppBundleId: bundleId)
        var variant = "ai-full"
        var displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "SweetGram"

        if let data = buildConfig.sgConfig.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let configuredVariant = json["sweetgram_variant"] as? String, !configuredVariant.isEmpty {
                variant = configuredVariant
            }
            if let branding = json["branding"] as? String, !branding.isEmpty {
                displayName = branding
            }
        }

        SweetGramIntegration.bootstrap(
            variantRaw: variant,
            bundleId: bundleId,
            displayName: displayName
        )

        if let context {
            attachAgentIfNeeded(context: context)
        }
    }

    public static func attachAgentIfNeeded(context: AccountContext) {
        guard SweetGramBootstrap.shared.featureFlags.agentServer else { return }
        let provider = AgentDataProvider(context: context)
        SweetGramIntegration.attachAgentDataProvider(provider)
    }
}
