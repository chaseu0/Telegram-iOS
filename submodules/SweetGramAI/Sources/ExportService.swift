import Foundation
import SweetGramCore

/// Handles exporting chat messages as text/JSON for AI consumption.
public enum ExportService {
    public enum ExportFormat: String, CaseIterable {
        case text = "txt"
        case json = "json"
        case markdown = "md"
    }

    public struct ExportResult {
        public let data: Data
        public let format: ExportFormat
        public let messageCount: Int
        public let filename: String
    }

    public static func export(
        chatTitle: String,
        messages: [(author: String, text: String, timestamp: Double)],
        format: ExportFormat,
        includeMetadata: Bool = true
    ) -> ExportResult {
        let count = messages.count
        let safeTitle = chatTitle.replacingOccurrences(of: "/", with: "-")

        switch format {
        case .text:
            let lines = messages.map { "[\(formatDate($0.timestamp))] \($0.author): \($0.text)" }
            let header = includeMetadata ? "Chat: \(chatTitle)\nMessages: \(count)\nExported: \(ISO8601DateFormatter().string(from: Date()))\n\n" : ""
            let content = header + lines.joined(separator: "\n")
            return ExportResult(
                data: content.data(using: .utf8) ?? Data(),
                format: .text,
                messageCount: count,
                filename: "\(safeTitle)-\(Int(Date().timeIntervalSince1970)).txt"
            )

        case .markdown:
            var md = includeMetadata ? """
            # Chat Export: \(chatTitle)
            - Messages: \(count)
            - Exported: \(ISO8601DateFormatter().string(from: Date()))

            ---

            """ : ""

            for msg in messages {
                md += "**\(msg.author)** (\(formatDate(msg.timestamp))):\n\(msg.text)\n\n"
            }
            return ExportResult(
                data: md.data(using: .utf8) ?? Data(),
                format: .markdown,
                messageCount: count,
                filename: "\(safeTitle)-\(Int(Date().timeIntervalSince1970)).md"
            )

        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let items = messages.map { msg in
                ExportMessage(author: msg.author, text: msg.text, timestamp: msg.timestamp)
            }
            let payload = ExportPayload(
                title: chatTitle,
                messageCount: count,
                exportedAt: ISO8601DateFormatter().string(from: Date()),
                messages: items
            )
            let data = (try? encoder.encode(payload)) ?? Data()
            return ExportResult(
                data: data,
                format: .json,
                messageCount: count,
                filename: "\(safeTitle)-\(Int(Date().timeIntervalSince1970)).json"
            )
        }
    }

    private struct ExportPayload: Codable {
        let title: String
        let messageCount: Int
        let exportedAt: String
        let messages: [ExportMessage]

        enum CodingKeys: String, CodingKey {
            case title
            case messageCount = "message_count"
            case exportedAt = "exported_at"
            case messages
        }
    }

    private struct ExportMessage: Codable {
        let author: String
        let text: String
        let timestamp: Double

        enum CodingKeys: String, CodingKey {
            case author, text, timestamp
        }
    }

    private static func formatDate(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.string(from: date)
    }
}
