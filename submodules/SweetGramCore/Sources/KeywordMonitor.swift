import Foundation

public struct MonitoredMessage: Equatable {
    public let chatId: Int64
    public let messageId: Int32
    public let senderName: String
    public let text: String
    public let deepLink: String?

    public init(
        chatId: Int64,
        messageId: Int32,
        senderName: String,
        text: String,
        deepLink: String? = nil
    ) {
        self.chatId = chatId
        self.messageId = messageId
        self.senderName = senderName
        self.text = text
        self.deepLink = deepLink
    }
}

public final class KeywordMonitor {
    public static let shared = KeywordMonitor()

    private var config = KeywordMonitorConfig()
    private var recentHits: [String: Date] = [:]
    private let queue = DispatchQueue(label: "com.sweetgram.keyword-monitor")

    private init() {}

    public func updateConfig(_ config: KeywordMonitorConfig) {
        queue.sync {
            self.config = config
        }
    }

    public func process(message: MonitoredMessage, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            guard self.config.enabled, !self.config.keywords.isEmpty else {
                completion?(false)
                return
            }

            let hits = self.matchedKeywords(in: message.text)
            guard !hits.isEmpty else {
                completion?(false)
                return
            }

            let dedupeKey = "\(message.chatId):\(message.messageId)"
            if self.isDuplicate(key: dedupeKey) {
                completion?(false)
                return
            }

            self.recentHits[dedupeKey] = Date()
            self.pruneOldHits()

            let title = "SweetGram · 关键词: \(hits.joined(separator: ", "))"
            let preview = message.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = "\(message.senderName): \(String(preview.prefix(180)))"

            BarkNotifier.shared.send(
                title: title,
                body: body,
                config: self.config.bark,
                url: message.deepLink
            ) { result in
                completion?(result.isSuccess)
            }
        }
    }

    private func matchedKeywords(in text: String) -> [String] {
        let hits = config.keywords.filter { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) }
        if config.matchMode == "all" {
            return hits.count == config.keywords.count ? config.keywords : []
        }
        return hits
    }

    private func isDuplicate(key: String) -> Bool {
        guard let last = recentHits[key] else { return false }
        let window = TimeInterval(config.dedupeMinutes * 60)
        return Date().timeIntervalSince(last) < window
    }

    private func pruneOldHits() {
        let cutoff = Date().addingTimeInterval(-86400)
        recentHits = recentHits.filter { $0.value > cutoff }
    }
}

private extension Result where Success == Void, Failure == Error {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
