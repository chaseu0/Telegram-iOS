import Foundation

public enum MessageContextLimit: Int, CaseIterable {
    case hundred = 100
    case fiveHundred = 500
    case thousand = 1000
    case twoThousand = 2000
    case full = 0

    public var label: String {
        switch self {
        case .hundred: return "100 messages"
        case .fiveHundred: return "500 messages"
        case .thousand: return "1000 messages"
        case .twoThousand: return "2000+ messages"
        case .full: return "Full history"
        }
    }

    public func apply(to messages: [String]) -> [String] {
        switch self {
        case .full:
            return messages
        default:
            return Array(messages.suffix(rawValue))
        }
    }
}

public struct RAGChatInput: Equatable {
    public let sessionId: Int64
    public let chatTitle: String
    public let contextMessages: [String]
    public let question: String

    public init(sessionId: Int64, chatTitle: String, contextMessages: [String], question: String) {
        self.sessionId = sessionId
        self.chatTitle = chatTitle
        self.contextMessages = contextMessages
        self.question = question
    }
}

public final class RAGChatService {
    public static let shared = RAGChatService()
    private let llmClient: LLMClient
    private let sessionStore: AIChatSessionStore

    public init(llmClient: LLMClient = .shared, sessionStore: AIChatSessionStore = .shared) {
        self.llmClient = llmClient
        self.sessionStore = sessionStore
    }

    public func ask(
        input: RAGChatInput,
        profile: CCSwitchProfile? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard SweetGramBootstrap.shared.featureFlags.aiChatSummary else {
            completion(.failure(ChatSummaryError.featureDisabled))
            return
        }

        let activeProfile = profile ?? LLMProfileManager.shared.activeProfile() ?? CCSwitchConfigReader.defaultProfile()
        guard let activeProfile else {
            completion(.failure(ChatSummaryError.noProfile))
            return
        }

        let prior = sessionStore.messages(for: input.sessionId)
        let transcript = input.contextMessages.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")

        var llmMessages: [LLMMessage] = [
            LLMMessage(role: "system", content: """
            You are SweetGram RAG assistant. Answer questions using ONLY the provided chat transcript.
            Chat: \(input.chatTitle)
            If the answer is not in the transcript, say you cannot find it.
            """)
        ]

        for msg in prior where msg.role == "user" || msg.role == "assistant" {
            llmMessages.append(LLMMessage(role: msg.role, content: msg.content))
        }

        llmMessages.append(LLMMessage(role: "user", content: """
        Transcript (\(input.contextMessages.count) messages):
        \(transcript)

        Question: \(input.question)
        """))

        sessionStore.appendMessage(sessionId: input.sessionId, role: "user", content: input.question)

        let request = LLMCompletionRequest(messages: llmMessages, model: activeProfile.model, maxTokens: 2048, temperature: 0.2)
        llmClient.complete(request: request, profile: activeProfile) { [weak self] result in
            switch result {
            case let .success(response):
                self?.sessionStore.appendMessage(sessionId: input.sessionId, role: "assistant", content: response.text)
                completion(.success(response.text))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}
