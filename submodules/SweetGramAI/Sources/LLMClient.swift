import Foundation

public struct LLMMessage: Codable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct LLMCompletionRequest {
    public let messages: [LLMMessage]
    public let model: String
    public let maxTokens: Int
    public let temperature: Double

    public init(
        messages: [LLMMessage],
        model: String,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) {
        self.messages = messages
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public struct LLMCompletionResponse: Equatable {
    public let text: String
    public let model: String
}

public enum LLMClientError: LocalizedError {
    case missingCredentials
    case invalidResponse
    case httpError(Int, String)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: return "LLM API key or base URL is missing"
        case .invalidResponse: return "Invalid LLM response"
        case let .httpError(code, body): return "LLM HTTP \(code): \(body)"
        case .decodingFailed: return "Failed to decode LLM response"
        }
    }
}

public final class LLMClient {
    public static let shared = LLMClient()
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func complete(
        request: LLMCompletionRequest,
        profile: CCSwitchProfile,
        completion: @escaping (Result<LLMCompletionResponse, Error>) -> Void
    ) {
        guard !profile.apiKey.isEmpty, !profile.baseURL.isEmpty else {
            completion(.failure(LLMClientError.missingCredentials))
            return
        }

        switch profile.apiFormat {
        case .anthropicMessages:
            completeAnthropic(request: request, profile: profile, completion: completion)
        case .openAICompletions:
            completeOpenAI(request: request, profile: profile, completion: completion)
        }
    }

    // MARK: - Anthropic Messages API

    private func completeAnthropic(
        request: LLMCompletionRequest,
        profile: CCSwitchProfile,
        completion: @escaping (Result<LLMCompletionResponse, Error>) -> Void
    ) {
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/messages") else {
            completion(.failure(LLMClientError.missingCredentials))
            return
        }

        var systemPrompt = ""
        var messages: [[String: String]] = []
        for msg in request.messages {
            if msg.role == "system" {
                systemPrompt = msg.content
            } else {
                messages.append(["role": msg.role, "content": msg.content])
            }
        }

        var body: [String: Any] = [
            "model": request.model.isEmpty ? profile.model : request.model,
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
            "messages": messages
        ]
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        sendJSON(url: url, body: body, headers: [
            "x-api-key": profile.apiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        ]) { result in
            switch result {
            case let .success(data):
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = json["content"] as? [[String: Any]],
                   let text = content.first?["text"] as? String {
                    completion(.success(LLMCompletionResponse(text: text, model: request.model)))
                } else {
                    completion(.failure(LLMClientError.decodingFailed))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - OpenAI Chat Completions API

    private func completeOpenAI(
        request: LLMCompletionRequest,
        profile: CCSwitchProfile,
        completion: @escaping (Result<LLMCompletionResponse, Error>) -> Void
    ) {
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = base.hasSuffix("/v1") ? "\(base)/chat/completions" : "\(base)/v1/chat/completions"
        guard let url = URL(string: path) else {
            completion(.failure(LLMClientError.missingCredentials))
            return
        }

        let body: [String: Any] = [
            "model": request.model.isEmpty ? profile.model : request.model,
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
            "messages": request.messages.map { ["role": $0.role, "content": $0.content] }
        ]

        sendJSON(url: url, body: body, headers: [
            "Authorization": "Bearer \(profile.apiKey)",
            "content-type": "application/json"
        ]) { result in
            switch result {
            case let .success(data):
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let text = message["content"] as? String {
                    completion(.success(LLMCompletionResponse(text: text, model: request.model)))
                } else {
                    completion(.failure(LLMClientError.decodingFailed))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func sendJSON(
        url: URL,
        body: [String: Any],
        headers: [String: String],
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(LLMClientError.invalidResponse))
                return
            }
            guard let data = data else {
                completion(.failure(LLMClientError.invalidResponse))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(LLMClientError.httpError(http.statusCode, body)))
                return
            }
            completion(.success(data))
        }.resume()
    }
}
