import Foundation
import Network

public struct AgentMessageDTO: Codable, Equatable {
    public let id: Int32
    public let author: String
    public let text: String
    public let timestamp: Double

    public init(id: Int32, author: String, text: String, timestamp: Double) {
        self.id = id
        self.author = author
        self.text = text
        self.timestamp = timestamp
    }
}

public struct AgentPeerProfileDTO: Codable, Equatable {
    public let peerId: Int64
    public let title: String
    public let username: String?
    public let bio: String?
    public let isGroup: Bool

    enum CodingKeys: String, CodingKey {
        case peerId = "peer_id"
        case title, username, bio
        case isGroup = "is_group"
    }
}

/// Injected by TelegramUI layer — keeps SweetGramAI free of Postbox/TelegramCore deps.
public protocol AgentDataProviding: AnyObject {
    func fetchMessages(peerId: Int64, limit: Int, completion: @escaping ([AgentMessageDTO]) -> Void)
    func fetchProfile(peerId: Int64, completion: @escaping (AgentPeerProfileDTO?) -> Void)
    func listContactPeerIds(completion: @escaping ([Int64]) -> Void)
    func listGroupPeerIds(completion: @escaping ([Int64]) -> Void)
}

public final class AgentHTTPServer {
    public static let shared = AgentHTTPServer()

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.sweetgram.agent-http")
    public weak var dataProvider: AgentDataProviding?

    private init() {}

    public var port: UInt16 {
        UInt16(SweetGramUserSettings.load().agentServerPort)
    }

    public var isRunning: Bool { listener != nil }

    public func start() {
        guard SweetGramBootstrap.shared.featureFlags.agentServer else { return }
        guard listener == nil else { return }

        let port = NWEndpoint.Port(rawValue: self.port) ?? 8787
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: port)
        } catch {
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener?.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    public func restart() {
        stop()
        start()
    }

    private func handle(connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error {
                connection.cancel()
                self.connections.removeAll { $0 === connection }
                return
            }
            var combined = buffer
            if let data = data { combined.append(data) }
            if isComplete || combined.containsEndOfHeaders {
                self.processRequest(data: combined, connection: connection)
            } else {
                self.receive(on: connection, buffer: combined)
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            respond(connection: connection, status: 400, body: ["error": "bad request"])
            return
        }

        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            respond(connection: connection, status: 400, body: ["error": "bad request line"])
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(connection: connection, status: 400, body: ["error": "bad request"])
            return
        }

        let method = String(parts[0])
        let path = String(parts[1]).components(separatedBy: "?").first ?? "/"
        let query = parseQuery(String(parts[1]))
        let bodyData = extractBody(from: data)

        switch method {
        case "GET":
            routeGET(path: path, query: query, connection: connection)
        case "POST":
            routePOST(path: path, body: bodyData, connection: connection)
        default:
            respond(connection: connection, status: 405, body: ["error": "method not allowed"])
        }
    }

    private func extractBody(from data: Data) -> Data {
        let marker = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: marker) else { return Data() }
        return data[range.upperBound...]
    }

    private func routeGET(path: String, query: [String: String], connection: NWConnection) {
        if path == "/health" {
            respond(connection: connection, status: 200, body: ["status": "ok", "port": Int(port)])
            return
        }

        if path == "/api/config/llm" {
            respondLLMConfig(connection: connection)
            return
        }

        guard let provider = dataProvider else {
            respond(connection: connection, status: 503, body: ["error": "data provider not ready"])
            return
        }

        let limit = Int(query["limit"] ?? "100") ?? 100

        if path == "/api/contacts" {
            provider.listContactPeerIds { ids in
                self.respond(connection: connection, status: 200, body: ["contacts": ids.map { Int($0) }])
            }
            return
        }

        if path == "/api/groups" {
            provider.listGroupPeerIds { ids in
                self.respond(connection: connection, status: 200, body: ["groups": ids.map { Int($0) }])
            }
            return
        }

        let contactMessagesPrefix = "/api/contacts/"
        if path.hasPrefix(contactMessagesPrefix) && path.hasSuffix("/messages") {
            let peerIdStr = path.dropFirst(contactMessagesPrefix.count).dropLast("/messages".count)
            guard let peerId = Int64(peerIdStr) else {
                respond(connection: connection, status: 400, body: ["error": "invalid peer id"])
                return
            }
            provider.fetchMessages(peerId: peerId, limit: limit) { messages in
                self.respond(connection: connection, status: 200, messages: messages, extra: ["peer_id": peerId])
            }
            return
        }

        let groupMessagesPrefix = "/api/groups/"
        if path.hasPrefix(groupMessagesPrefix) && path.contains("/messages") {
            let remainder = path.dropFirst(groupMessagesPrefix.count)
            if let slash = remainder.firstIndex(of: "/") {
                let peerIdStr = remainder[..<slash]
                guard let peerId = Int64(peerIdStr) else {
                    respond(connection: connection, status: 400, body: ["error": "invalid peer id"])
                    return
                }
                let suffix = remainder[slash...]
                let effectiveLimit = suffix.contains("full") ? 10_000 : limit
                provider.fetchMessages(peerId: peerId, limit: effectiveLimit) { messages in
                    self.respond(connection: connection, status: 200, messages: messages, extra: ["peer_id": peerId, "count": messages.count])
                }
                return
            }
        }

        if path.hasPrefix("/api/contacts/") && path.hasSuffix("/profile") {
            let peerIdStr = path.dropFirst("/api/contacts/".count).dropLast("/profile".count)
            guard let peerId = Int64(peerIdStr) else {
                respond(connection: connection, status: 400, body: ["error": "invalid peer id"])
                return
            }
            provider.fetchProfile(peerId: peerId) { profile in
                if let profile {
                    self.respond(connection: connection, status: 200, body: profile)
                } else {
                    self.respond(connection: connection, status: 404, body: ["error": "not found"])
                }
            }
            return
        }

        if path.hasPrefix("/api/contacts/") && path.hasSuffix("/bio") {
            let peerIdStr = path.dropFirst("/api/contacts/".count).dropLast("/bio".count)
            guard let peerId = Int64(peerIdStr) else {
                respond(connection: connection, status: 400, body: ["error": "invalid peer id"])
                return
            }
            provider.fetchProfile(peerId: peerId) { profile in
                self.respond(connection: connection, status: 200, body: ["peer_id": peerId, "bio": profile?.bio ?? ""])
            }
            return
        }

        if path.hasPrefix("/api/contacts/") && path.hasSuffix("/bio/groups") {
            let peerIdStr = path.dropFirst("/api/contacts/".count).dropLast("/bio/groups".count)
            guard let peerId = Int64(peerIdStr) else {
                respond(connection: connection, status: 400, body: ["error": "invalid peer id"])
                return
            }
            provider.fetchProfile(peerId: peerId) { profile in
                let groups = Self.extractGroupLinks(from: profile?.bio ?? "")
                self.respond(connection: connection, status: 200, body: ["peer_id": peerId, "groups": groups])
            }
            return
        }

        if path.hasPrefix("/api/groups/") && path.hasSuffix("/preview") {
            let peerIdStr = path.dropFirst("/api/groups/".count).dropLast("/preview".count)
            guard let peerId = Int64(peerIdStr) else {
                respond(connection: connection, status: 400, body: ["error": "invalid peer id"])
                return
            }
            provider.fetchMessages(peerId: peerId, limit: min(limit, 50)) { messages in
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(messages),
                   let preview = try? JSONSerialization.jsonObject(with: data) {
                    self.respond(connection: connection, status: 200, jsonObject: ["peer_id": peerId, "preview": preview])
                }
            }
            return
        }

        respond(connection: connection, status: 404, body: ["error": "not found", "path": path])
    }

    private func routePOST(path: String, body: Data, connection: NWConnection) {
        if path == "/api/config/llm" {
            applyLLMConfig(body: body, connection: connection)
            return
        }
        respond(connection: connection, status: 404, body: ["error": "not found", "path": path])
    }

    private struct LLMConfigPayload: Decodable {
        let name: String?
        let baseURL: String?
        let model: String?
        let apiKey: String?
        let profileId: String?

        enum CodingKeys: String, CodingKey {
            case name, model
            case baseURL = "base_url"
            case apiKey = "api_key"
            case profileId = "profile_id"
        }
    }

    private func respondLLMConfig(connection: NWConnection) {
        guard let profile = LLMProfileManager.shared.activeProfile() else {
            respond(connection: connection, status: 404, body: ["error": "no active llm profile"])
            return
        }
        let settings = SweetGramUserSettings.load()
        respond(connection: connection, status: 200, body: [
            "profile_id": settings.selectedLLMProfileId ?? LLMProfileManager.shared.activeProfileId() ?? "",
            "name": profile.name,
            "base_url": profile.baseURL,
            "model": profile.model,
            "api_key_masked": LLMProfileManager.shared.maskedApiKey(
                for: settings.selectedLLMProfileId ?? LLMProfileManager.shared.activeProfileId() ?? ""
            ),
            "api_format": profile.apiFormat.rawValue
        ])
    }

    private func applyLLMConfig(body: Data, connection: NWConnection) {
        guard let payload = try? JSONDecoder().decode(LLMConfigPayload.self, from: body) else {
            respond(connection: connection, status: 400, body: ["error": "invalid json body"])
            return
        }

        let baseURL = payload.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = payload.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "LAN Import"
        guard !baseURL.isEmpty, !model.isEmpty else {
            respond(connection: connection, status: 400, body: ["error": "base_url and model are required"])
            return
        }

        let profile = LLMProfileManager.shared.upsertProfile(
            id: payload.profileId,
            name: name,
            baseURL: baseURL,
            model: model,
            apiKey: payload.apiKey ?? ""
        )
        LLMProfileManager.shared.selectProfile(id: profile.id)

        respond(connection: connection, status: 200, body: [
            "status": "ok",
            "profile_id": profile.id,
            "name": profile.name,
            "base_url": profile.baseURL,
            "model": profile.model,
            "api_key_set": !(payload.apiKey ?? "").isEmpty || LLMProfileManager.shared.maskedApiKey(for: profile.id) != "(not set)"
        ])
    }

    private static func extractGroupLinks(from bio: String) -> [String] {
        let pattern = #"(@\w+|https?://t\.me/\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(bio.startIndex..., in: bio)
        return regex.matches(in: bio, range: range).compactMap {
            Range($0.range, in: bio).map { String(bio[$0]) }
        }
    }

    private func parseQuery(_ raw: String) -> [String: String] {
        guard let qIndex = raw.firstIndex(of: "?") else { return [:] }
        let query = raw[raw.index(after: qIndex)...]
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return result
    }

    private func respond(connection: NWConnection, status: Int, jsonObject: Any) {
        guard JSONSerialization.isValidJSONObject(jsonObject),
              let json = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
              let jsonString = String(data: json, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let response = """
        HTTP/1.1 \(status) \(statusText(status))\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        Content-Length: \(jsonString.utf8.count)\r
        \r
        \(jsonString)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
            self.connections.removeAll { $0 === connection }
        })
    }

    private func respond(connection: NWConnection, status: Int, body: [String: Any]) {
        respond(connection: connection, status: status, jsonObject: body)
    }

    private func respond(connection: NWConnection, status: Int, body: AgentPeerProfileDTO) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(body),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            connection.cancel()
            return
        }
        respond(connection: connection, status: status, jsonObject: dict)
    }

    private func respond(connection: NWConnection, status: Int, messages: [AgentMessageDTO], extra: [String: Any] = [:]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(messages),
              let array = try? JSONSerialization.jsonObject(with: data) else {
            connection.cancel()
            return
        }
        var body = extra
        body["messages"] = array
        respond(connection: connection, status: status, jsonObject: body)
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }
}

private extension Data {
    var containsEndOfHeaders: Bool {
        let marker = Data("\r\n\r\n".utf8)
        return range(of: marker) != nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

