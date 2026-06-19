import Foundation
import SweetGramCore
import SweetGramAI

/// Entry point called from TelegramUI after account context is ready.
public enum SweetGramIntegration {
    public static func bootstrap(
        variantRaw: String,
        bundleId: String,
        displayName: String
    ) {
        let variant = SweetGramVariant(rawValue: variantRaw) ?? .original
        SweetGramBootstrap.shared.configure(
            variant: variant,
            bundleId: bundleId,
            displayName: displayName
        )
        SweetGramSettingsStore.applyPersistedSettings()
        if SweetGramBootstrap.shared.featureFlags.aiLlmSettings {
            LLMSettingsPresenter.shared.reload()
        }
        if SweetGramBootstrap.shared.featureFlags.agentServer {
            let settings = SweetGramUserSettings.load()
            if settings.agentServerEnabled {
                AgentHTTPServer.shared.restart()
            }
        }
    }

    public static func attachAgentDataProvider(_ provider: AgentDataProviding) {
        AgentHTTPServer.shared.dataProvider = provider
        if SweetGramBootstrap.shared.featureFlags.agentServer {
            let settings = SweetGramUserSettings.load()
            if settings.agentServerEnabled {
                AgentHTTPServer.shared.restart()
            }
        }
    }

    /// Wire into message pipeline for keyword monitoring (AI Full variant).
    public static func onIncomingMessage(
        chatId: Int64,
        messageId: Int32,
        senderName: String,
        text: String,
        deepLink: String?
    ) {
        guard SweetGramBootstrap.shared.featureFlags.keywordMonitor else { return }
        let message = MonitoredMessage(
            chatId: chatId,
            messageId: messageId,
            senderName: senderName,
            text: text,
            deepLink: deepLink
        )
        KeywordMonitor.shared.process(message: message)
    }

    /// Wire into chat context menu / toolbar for group summary.
    public static func summarizeChat(
        title: String,
        messages: [String],
        maxMessages: Int = 200,
        completion: @escaping (Result<ChatSummaryResult, Error>) -> Void
    ) {
        ChatSummaryService.shared.summarize(
            input: ChatSummaryInput(chatTitle: title, messages: messages, maxMessages: maxMessages),
            completion: completion
        )
    }

    public static func askRAG(
        sessionId: Int64,
        title: String,
        messages: [String],
        question: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        RAGChatService.shared.ask(
            input: RAGChatInput(sessionId: sessionId, chatTitle: title, contextMessages: messages, question: question),
            completion: completion
        )
    }

    public static func createAISession(peerId: Int64, title: String, messageLimit: Int) -> AIChatSession? {
        AIChatSessionStore.shared.createSession(peerId: peerId, title: title, messageLimit: messageLimit)
    }
}
