import Foundation

public struct ChatSummaryInput: Equatable {
    public let chatTitle: String
    public let messages: [String]
    public let maxMessages: Int

    public init(chatTitle: String, messages: [String], maxMessages: Int = 200) {
        self.chatTitle = chatTitle
        self.messages = messages
        self.maxMessages = maxMessages
    }
}

public struct ChatSummaryResult: Equatable {
    public let summary: String
    public let topics: [String]
    public let messageCount: Int
}

public enum ChatSummaryError: LocalizedError {
    case featureDisabled
    case noMessages
    case noProfile

    public var errorDescription: String? {
        switch self {
        case .featureDisabled: return "Chat summary is disabled in this variant"
        case .noMessages: return "No messages to summarize"
        case .noProfile: return "No LLM profile configured. Import CC Switch config in Settings."
        }
    }
}

public final class ChatSummaryService {
    public static let shared = ChatSummaryService()
    private let llmClient: LLMClient

    public init(llmClient: LLMClient = .shared) {
        self.llmClient = llmClient
    }

    public func summarize(
        input: ChatSummaryInput,
        profile: CCSwitchProfile? = nil,
        modelOverride: String? = nil,
        completion: @escaping (Result<ChatSummaryResult, Error>) -> Void
    ) {
        guard SweetGramBootstrap.shared.featureFlags.aiChatSummary else {
            completion(.failure(ChatSummaryError.featureDisabled))
            return
        }

        let trimmed = input.messages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !trimmed.isEmpty else {
            completion(.failure(ChatSummaryError.noMessages))
            return
        }

        let activeProfile = profile ?? LLMProfileManager.shared.activeProfile() ?? CCSwitchConfigReader.defaultProfile()
        guard let activeProfile else {
            completion(.failure(ChatSummaryError.noProfile))
            return
        }

        let selected = Array(trimmed.suffix(input.maxMessages))
        let transcript = selected.enumerated().map { idx, line in
            "[\(idx + 1)] \(line)"
        }.joined(separator: "\n")

        let system = """
        你是 SweetGram 群聊总结助手。请用中文输出：
        1) 一段简洁的群聊总结（bullet points 优先）
        2) 单独一行输出 TOPICS: 后跟 3-5 个关键词，用逗号分隔
        只基于提供的消息，不要编造。
        """

        let user = """
        群名称: \(input.chatTitle)
        消息条数: \(selected.count)

        聊天记录:
        \(transcript)
        """

        let request = LLMCompletionRequest(
            messages: [
                LLMMessage(role: "system", content: system),
                LLMMessage(role: "user", content: user)
            ],
            model: modelOverride ?? activeProfile.model,
            maxTokens: 2048,
            temperature: 0.2
        )

        llmClient.complete(request: request, profile: activeProfile) { result in
            switch result {
            case let .success(response):
                let parsed = Self.parseSummary(response.text, messageCount: selected.count)
                completion(.success(parsed))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private static func parseSummary(_ text: String, messageCount: Int) -> ChatSummaryResult {
        var summary = text
        var topics: [String] = []

        if let range = text.range(of: "TOPICS:", options: .caseInsensitive) {
            summary = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let topicLine = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            topics = topicLine
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return ChatSummaryResult(summary: summary, topics: topics, messageCount: messageCount)
    }
}
