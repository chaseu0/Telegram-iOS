import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import AccountContext
import AppBundle
import LocalizedPeerData
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import ContextUI
import OverlayStatusController
import PresentationDataUtils
import AlertUI
import SweetGramIntegration
import SweetGramAI
import SweetGramCore

public enum SweetGramChatMenuHook {
    public static func appendChatSummaryMenuItem(
        context: AccountContext,
        sourceController: ViewController,
        peerId: EnginePeer.Id,
        items: inout [ContextMenuItem]
    ) {
        guard SweetGramBootstrap.shared.featureFlags.aiChatSummary else { return }

        items.append(.separator)
        items.append(.action(ContextMenuActionItem(
            text: "AI Summary & Q&A",
            icon: { theme in
                generateTintedImage(
                    image: UIImage(bundleImageName: "Chat/Context Menu/Translate"),
                    color: theme.contextMenu.primaryColor
                )
            },
            action: { [weak sourceController] action in
                action.dismissWithResult(.default)
                guard let sourceController else { return }
                presentMessageLimitPicker(
                    context: context,
                    sourceController: sourceController,
                    peerId: peerId
                )
            }
        )))
    }

    private static func presentMessageLimitPicker(
        context: AccountContext,
        sourceController: ViewController,
        peerId: EnginePeer.Id
    ) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alert = UIAlertController(title: "AI Context", message: "Choose how many messages to include", preferredStyle: .actionSheet)

        for limit in MessageContextLimit.allCases {
            alert.addAction(UIAlertAction(title: limit.label, style: .default) { _ in
                presentActionPicker(
                    context: context,
                    sourceController: sourceController,
                    peerId: peerId,
                    limit: limit
                )
            })
        }
        alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }

    private static func presentActionPicker(
        context: AccountContext,
        sourceController: ViewController,
        peerId: EnginePeer.Id,
        limit: MessageContextLimit
    ) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alert = UIAlertController(title: "SweetGram AI", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Summarize", style: .default) { _ in
            runSummary(context: context, sourceController: sourceController, peerId: peerId, limit: limit)
        })
        alert.addAction(UIAlertAction(title: "Ask Question (RAG)", style: .default) { _ in
            promptRAGQuestion(context: context, sourceController: sourceController, peerId: peerId, limit: limit)
        })
        alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }

    private static func loadMessages(
        context: AccountContext,
        peerId: EnginePeer.Id,
        limit: MessageContextLimit,
        completion: @escaping (String, [String]) -> Void
    ) {
        let fetchCount = limit == .full ? 5000 : max(limit.rawValue, 100)
        let historySignal = context.account.postbox.aroundMessageHistoryViewForLocation(
            .peer(peerId: peerId, threadId: nil),
            anchor: .upperBound,
            ignoreMessagesInTimestampRange: nil,
            ignoreMessageIds: Set(),
            count: fetchCount,
            fixedCombinedReadStates: nil,
            topTaggedMessageIdNamespaces: Set(),
            tag: nil,
            appendMessagesFromTheSameGroup: false,
            namespaces: .not(Namespaces.Message.allNonRegular),
            orderStatistics: []
        )
        |> take(1)
        |> mapToSignal { view, _, _ -> Signal<(String, [String]), NoError> in
            context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> map { peer in
                let chatTitle = peer?.compactDisplayTitle ?? "Chat"
                let lines = view.entries.compactMap { entry -> String? in
                    guard let message = message(from: entry) else { return nil }
                    let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    let author = authorTitle(message.author)
                    return "\(author): \(text)"
                }
                return (chatTitle, limit.apply(to: lines))
            }
        }

        let _ = (historySignal
        |> deliverOnMainQueue).startStandalone(next: { result in
            completion(result.0, result.1)
        })
    }

    private static func runSummary(
        context: AccountContext,
        sourceController: ViewController,
        peerId: EnginePeer.Id,
        limit: MessageContextLimit
    ) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
        sourceController.present(statusController, in: .window(.root))

        loadMessages(context: context, peerId: peerId, limit: limit) { chatTitle, lines in
            SweetGramIntegration.summarizeChat(title: chatTitle, messages: lines, maxMessages: limit.rawValue > 0 ? limit.rawValue : lines.count) { result in
                DispatchQueue.main.async {
                    statusController.dismiss()
                    switch result {
                    case let .success(summary):
                        let topics = summary.topics.isEmpty ? "" : "\n\nTopics: \(summary.topics.joined(separator: ", "))"
                        let alertController = UIAlertController(
                            title: "Summary (\(summary.messageCount) msgs)",
                            message: summary.summary + topics,
                            preferredStyle: .alert
                        )
                        alertController.addAction(UIAlertAction(title: presentationData.strings.Common_OK, style: .default))
                        context.sharedContext.applicationBindings.presentNativeController(alertController)
                    case let .failure(error):
                        let alertController = UIAlertController(
                            title: "Summary failed",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        alertController.addAction(UIAlertAction(title: presentationData.strings.Common_OK, style: .default))
                        context.sharedContext.applicationBindings.presentNativeController(alertController)
                    }
                }
            }
        }
    }

    private static func promptRAGQuestion(
        context: AccountContext,
        sourceController: ViewController,
        peerId: EnginePeer.Id,
        limit: MessageContextLimit
    ) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alertController = UIAlertController(title: "Ask about this chat", message: nil, preferredStyle: .alert)
        alertController.addTextField { field in
            field.placeholder = "Your question"
        }
        alertController.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
        alertController.addAction(UIAlertAction(title: "Ask", style: .default) { _ in
            let question = alertController.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !question.isEmpty else { return }
            runRAG(context: context, sourceController: sourceController, peerId: peerId, limit: limit, question: question)
        })
        context.sharedContext.applicationBindings.presentNativeController(alertController)
    }

    private static func runRAG(
        context: AccountContext,
        sourceController: ViewController,
        peerId: EnginePeer.Id,
        limit: MessageContextLimit,
        question: String
    ) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
        sourceController.present(statusController, in: .window(.root))

        loadMessages(context: context, peerId: peerId, limit: limit) { chatTitle, lines in
            let session = SweetGramIntegration.createAISession(
                peerId: peerId.toInt64(),
                title: chatTitle,
                messageLimit: limit == .full ? lines.count : limit.rawValue
            )
            guard let session else {
                statusController.dismiss()
                return
            }
            SweetGramIntegration.askRAG(sessionId: session.id, title: chatTitle, messages: lines, question: question) { result in
                DispatchQueue.main.async {
                    statusController.dismiss()
                    switch result {
                    case let .success(answer):
                        let alertController = UIAlertController(
                            title: "AI Answer",
                            message: answer,
                            preferredStyle: .alert
                        )
                        alertController.addAction(UIAlertAction(title: presentationData.strings.Common_OK, style: .default))
                        context.sharedContext.applicationBindings.presentNativeController(alertController)
                    case let .failure(error):
                        let alertController = UIAlertController(
                            title: "RAG failed",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        alertController.addAction(UIAlertAction(title: presentationData.strings.Common_OK, style: .default))
                        context.sharedContext.applicationBindings.presentNativeController(alertController)
                    }
                }
            }
        }
    }

    private static func authorTitle(_ author: Peer?) -> String {
        guard let author else { return "Unknown" }
        return EnginePeer(author).compactDisplayTitle
    }

    private static func message(from entry: MessageHistoryEntry) -> Message? {
        return entry.message
    }
}
