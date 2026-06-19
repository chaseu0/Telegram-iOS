import Foundation
import Postbox
import TelegramCore
import TelegramStringFormatting
import AccountContext
import ChatHistoryEntry
import SweetGramIntegration
import SweetGramCore

enum SweetGramMessagePipelineHook {
    static func processHistoryViewUpdate(
        context: AccountContext,
        chatLocation: ChatLocation,
        previous: ChatHistoryView?,
        current: ChatHistoryView,
        urlScheme: String
    ) {
        guard SweetGramBootstrap.shared.featureFlags.keywordMonitor else { return }

        let accountPeerId = context.account.peerId
        let previousIds = Set(
            (previous?.filteredEntries ?? [])
                .compactMap { message(from: $0)?.id }
        )
        let chatPeerId = chatLocation.peerId ?? message(from: current.filteredEntries.first)?.id.peerId

        for entry in current.filteredEntries {
            guard let message = message(from: entry) else { continue }
            guard !previousIds.contains(message.id) else { continue }
            guard message.effectivelyIncoming(accountPeerId) else { continue }
            guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let peerId = chatPeerId ?? message.id.peerId
            let deepLink = "\(urlScheme)://chat?peer=\(peerId.toInt64())&message=\(message.id.id)"
            let senderName = message.author?.compactDisplayTitle ?? "Unknown"

            SweetGramIntegration.onIncomingMessage(
                chatId: peerId.toInt64(),
                messageId: message.id.id,
                senderName: senderName,
                text: message.text,
                deepLink: deepLink
            )
        }
    }

    private static func message(from entry: ChatHistoryEntry) -> Message? {
        switch entry {
        case let .MessageEntry(message, _, _, _, _, _):
            return message
        case let .MessageGroupEntry(_, messages, _):
            return messages.first?.0
        default:
            return nil
        }
    }
}
