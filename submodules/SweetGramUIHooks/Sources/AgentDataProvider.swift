import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import SweetGramAI
import LocalizedPeerData

/// Bridges Telegram postbox/engine data to the local Agent HTTP API.
public final class AgentDataProvider: AgentDataProviding {
    private weak var context: AccountContext?

    public init(context: AccountContext) {
        self.context = context
    }

    public func fetchMessages(peerId: Int64, limit: Int, completion: @escaping ([AgentMessageDTO]) -> Void) {
        guard let context else {
            completion([])
            return
        }
        let enginePeerId = EnginePeer.Id(peerId)

        let _ = (context.account.postbox.aroundMessageHistoryViewForLocation(
            .peer(peerId: enginePeerId, threadId: nil),
            anchor: .upperBound,
            ignoreMessagesInTimestampRange: nil,
            ignoreMessageIds: Set(),
            count: max(limit, 1),
            fixedCombinedReadStates: nil,
            topTaggedMessageIdNamespaces: Set(),
            tag: nil,
            appendMessagesFromTheSameGroup: false,
            namespaces: .not(Namespaces.Message.allNonRegular),
            orderStatistics: []
        )
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { view, _, _ in
            let messages = view.entries.compactMap { entry -> AgentMessageDTO? in
                guard let message = Self.message(from: entry) else { return nil }
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return AgentMessageDTO(
                    id: message.id.id,
                    author: Self.authorTitle(message.author),
                    text: text,
                    timestamp: Double(message.timestamp)
                )
            }
            completion(messages)
        })
    }

    public func fetchProfile(peerId: Int64, completion: @escaping (AgentPeerProfileDTO?) -> Void) {
        guard let context else {
            completion(nil)
            return
        }
        let enginePeerId = EnginePeer.Id(peerId)
        let _ = (context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: enginePeerId),
            TelegramEngine.EngineData.Item.Peer.AboutText(id: enginePeerId)
        )
        |> deliverOnMainQueue).startStandalone(next: { peer, aboutItem in
            guard let peer else {
                completion(nil)
                return
            }
            let isGroup: Bool
            switch peer {
            case .channel, .legacyGroup:
                isGroup = true
            default:
                isGroup = false
            }
            let about: String?
            if case let .known(value) = aboutItem {
                about = value
            } else {
                about = nil
            }
            completion(AgentPeerProfileDTO(
                peerId: peerId,
                title: peer.compactDisplayTitle,
                username: peer.addressName,
                bio: about,
                isGroup: isGroup
            ))
        })
    }

    public func listContactPeerIds(completion: @escaping ([Int64]) -> Void) {
        guard let context else {
            completion([])
            return
        }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Contacts.List(includePresences: false))
        |> deliverOnMainQueue).startStandalone(next: { list in
            let ids = list.peers.map { $0.id.toInt64() }
            completion(ids)
        })
    }

    public func listGroupPeerIds(completion: @escaping ([Int64]) -> Void) {
        guard let context else {
            completion([])
            return
        }
        let _ = (context.engine.messages.chatList(group: .root, count: 200)
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { list in
            var ids: [Int64] = []
            for item in list.items {
                guard let peer = item.renderedPeer.chatMainPeer else { continue }
                switch peer {
                case let .channel(channel):
                    if case .group = channel.info {
                        ids.append(peer.id.toInt64())
                    }
                case .legacyGroup:
                    ids.append(peer.id.toInt64())
                default:
                    break
                }
            }
            completion(ids)
        })
    }

    private static func authorTitle(_ author: Peer?) -> String {
        guard let author else { return "Unknown" }
        return EnginePeer(author).compactDisplayTitle
    }

    private static func message(from entry: MessageHistoryEntry) -> Message {
        return entry.message
    }
}
