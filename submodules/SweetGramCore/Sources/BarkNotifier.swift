import Foundation

public struct BarkConfig: Codable, Equatable {
    public var serverURL: String
    public var deviceKey: String
    public var group: String?
    public var sound: String?
    public var icon: String?

    public init(
        serverURL: String = "https://api.day.app",
        deviceKey: String = "",
        group: String? = "SweetGram",
        sound: String? = "default",
        icon: String? = nil
    ) {
        self.serverURL = serverURL
        self.deviceKey = deviceKey
        self.group = group
        self.sound = sound
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey {
        case serverURL = "server_url"
        case deviceKey = "device_key"
        case group, sound, icon
    }

    public var isConfigured: Bool {
        !deviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct KeywordMonitorConfig: Codable, Equatable {
    public var enabled: Bool
    public var keywords: [String]
    public var matchMode: String
    public var dedupeMinutes: Int
    public var bark: BarkConfig

    public init(
        enabled: Bool = false,
        keywords: [String] = [],
        matchMode: String = "any",
        dedupeMinutes: Int = 30,
        bark: BarkConfig = BarkConfig()
    ) {
        self.enabled = enabled
        self.keywords = keywords
        self.matchMode = matchMode
        self.dedupeMinutes = dedupeMinutes
        self.bark = bark
    }

    enum CodingKeys: String, CodingKey {
        case enabled, keywords
        case matchMode = "match_mode"
        case dedupeMinutes = "dedupe_minutes"
        case bark
    }
}

public final class BarkNotifier {
    public static let shared = BarkNotifier()
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(
        title: String,
        body: String,
        config: BarkConfig,
        url: String? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard config.isConfigured else {
            completion?(.failure(BarkError.notConfigured))
            return
        }

        let base = config.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? body
        var endpoint = "\(base)/\(config.deviceKey)/\(encodedTitle)/\(encodedBody)"

        var queryItems: [URLQueryItem] = []
        if let group = config.group, !group.isEmpty {
            queryItems.append(URLQueryItem(name: "group", value: group))
        }
        if let sound = config.sound, !sound.isEmpty {
            queryItems.append(URLQueryItem(name: "sound", value: sound))
        }
        if let icon = config.icon, !icon.isEmpty {
            queryItems.append(URLQueryItem(name: "icon", value: icon))
        }
        if let url = url, !url.isEmpty {
            queryItems.append(URLQueryItem(name: "url", value: url))
        }

        if !queryItems.isEmpty {
            var components = URLComponents(string: endpoint)
            components?.queryItems = queryItems
            endpoint = components?.url?.absoluteString ?? endpoint
        }

        guard let requestURL = URL(string: endpoint) else {
            completion?(.failure(BarkError.invalidURL))
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                completion?(.failure(BarkError.requestFailed))
                return
            }
            completion?(.success(()))
        }.resume()
    }
}

public enum BarkError: LocalizedError {
    case notConfigured
    case invalidURL
    case requestFailed

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Bark device key is not configured"
        case .invalidURL: return "Invalid Bark URL"
        case .requestFailed: return "Bark push request failed"
        }
    }
}
