import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import LegacyMediaPickerUI
import SweetGramIntegration
import SweetGramAI
import SweetGramCore

private final class SweetGramLLMSettingsArguments {
    let context: AccountContext
    let selectProfile: (String) -> Void
    let addProfile: () -> Void
    let editProfile: (String) -> Void
    let importConfig: () -> Void
    let runTest: () -> Void
    let configureAgent: () -> Void

    init(
        context: AccountContext,
        selectProfile: @escaping (String) -> Void,
        addProfile: @escaping () -> Void,
        editProfile: @escaping (String) -> Void,
        importConfig: @escaping () -> Void,
        runTest: @escaping () -> Void,
        configureAgent: @escaping () -> Void
    ) {
        self.context = context
        self.selectProfile = selectProfile
        self.addProfile = addProfile
        self.editProfile = editProfile
        self.importConfig = importConfig
        self.runTest = runTest
        self.configureAgent = configureAgent
    }
}

private enum SweetGramLLMSettingsSection: Int32 {
    case profiles
    case actions
    case agent
}

private enum SweetGramLLMSettingsEntry: ItemListNodeEntry {
    case header(String)
    case profile(id: String, title: String, subtitle: String, selected: Bool)
    case addProfile
    case importConfig
    case connectivityTest
    case agentHeader
    case agentPort(String)
    case agentStatus(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .profile, .addProfile:
            return SweetGramLLMSettingsSection.profiles.rawValue
        case .importConfig, .connectivityTest:
            return SweetGramLLMSettingsSection.actions.rawValue
        case .agentHeader, .agentPort, .agentStatus:
            return SweetGramLLMSettingsSection.agent.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .header: return 0
        case let .profile(id, _, _, _): return id.hashValue
        case .addProfile: return 10_000
        case .importConfig: return 10_001
        case .connectivityTest: return 10_002
        case .agentHeader: return 20_000
        case .agentPort: return 20_001
        case .agentStatus: return 20_002
        }
    }

    static func == (lhs: SweetGramLLMSettingsEntry, rhs: SweetGramLLMSettingsEntry) -> Bool {
        switch lhs {
        case let .header(lhsText):
            if case let .header(rhsText) = rhs { return lhsText == rhsText }
            return false
        case let .profile(lhsId, lhsTitle, lhsSubtitle, lhsSelected):
            if case let .profile(rhsId, rhsTitle, rhsSubtitle, rhsSelected) = rhs {
                return lhsId == rhsId && lhsTitle == rhsTitle && lhsSubtitle == rhsSubtitle && lhsSelected == rhsSelected
            }
            return false
        case .addProfile:
            if case .addProfile = rhs { return true }
            return false
        case .importConfig:
            if case .importConfig = rhs { return true }
            return false
        case .connectivityTest:
            if case .connectivityTest = rhs { return true }
            return false
        case .agentHeader:
            if case .agentHeader = rhs { return true }
            return false
        case let .agentPort(lhsText):
            if case let .agentPort(rhsText) = rhs { return lhsText == rhsText }
            return false
        case let .agentStatus(lhsText):
            if case let .agentStatus(rhsText) = rhs { return lhsText == rhsText }
            return false
        }
    }

    static func < (lhs: SweetGramLLMSettingsEntry, rhs: SweetGramLLMSettingsEntry) -> Bool {
        lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SweetGramLLMSettingsArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .profile(id, title, subtitle, selected):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                subtitle: subtitle,
                style: .left,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: { arguments.selectProfile(id) }
            )
        case .addProfile:
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "Add OpenAI-Compatible API",
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { arguments.addProfile() }
            )
        case .importConfig:
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "Import CC Switch Config",
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { arguments.importConfig() }
            )
        case .connectivityTest:
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "Test LLM Connection",
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { arguments.runTest() }
            )
        case .agentHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Local Agent API", sectionId: self.section)
        case let .agentPort(text):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: text,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { arguments.configureAgent() }
            )
        case let .agentStatus(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct SweetGramLLMSettingsState: Equatable {
    var refreshToken: Int = 0
}

private func sweetGramLLMSettingsEntries(presentationData: PresentationData) -> [SweetGramLLMSettingsEntry] {
    guard LLMSettingsPresenter.shared.isAvailable else { return [] }

    var entries: [SweetGramLLMSettingsEntry] = []
    entries.append(.header("LLM Profiles (OpenAI-compatible)"))

    let settings = SweetGramUserSettings.load()
    let activeId = settings.selectedLLMProfileId ?? LLMProfileManager.shared.activeProfileId()
    for row in LLMSettingsPresenter.shared.profileRows() {
        entries.append(.profile(id: row.id, title: row.title, subtitle: row.subtitle, selected: row.id == activeId))
    }

    entries.append(.addProfile)
    entries.append(.importConfig)
    entries.append(.connectivityTest)

    if SweetGramBootstrap.shared.featureFlags.agentServer {
        entries.append(.agentHeader)
        entries.append(.agentPort("Port: \(settings.agentServerPort) (LAN accessible)"))
        let status = AgentHTTPServer.shared.isRunning ? "Status: running" : "Status: stopped"
        entries.append(.agentStatus(status))
    }

    return entries
}

public func sweetGramLLMSettingsController(context: AccountContext) -> ViewController {
    let initialState = SweetGramLLMSettingsState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SweetGramLLMSettingsState) -> SweetGramLLMSettingsState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var hostController: ViewController?

    let arguments = SweetGramLLMSettingsArguments(
        context: context,
        selectProfile: { profileId in
            LLMSettingsPresenter.shared.selectProfile(id: profileId)
            updateState { state in
                var updated = state
                updated.refreshToken &+= 1
                return updated
            }
        },
        addProfile: {
            presentProfileEditor(
                context: context,
                profileId: nil,
                present: { context.sharedContext.applicationBindings.presentNativeController($0) },
                onSave: {
                    updateState { state in
                        var updated = state
                        updated.refreshToken &+= 1
                        return updated
                    }
                }
            )
        },
        editProfile: { profileId in
            presentProfileEditor(
                context: context,
                profileId: profileId,
                present: { context.sharedContext.applicationBindings.presentNativeController($0) },
                onSave: {
                    updateState { state in
                        var updated = state
                        updated.refreshToken &+= 1
                        return updated
                    }
                }
            )
        },
        importConfig: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let picker = legacyICloudFilePicker(
                theme: presentationData.theme,
                mode: .import,
                documentTypes: ["public.json"],
                completion: { urls in
                    guard let url = urls.first else { return }
                    do {
                        try LLMSettingsPresenter.shared.importCCSwitchJSON(from: url)
                        updateState { state in
                            var updated = state
                            updated.refreshToken &+= 1
                            return updated
                        }
                    } catch {
                        let alert = textAlertController(
                            context: context,
                            title: "Import Failed",
                            text: error.localizedDescription,
                            actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                        )
                        presentControllerImpl?(alert, nil)
                    }
                }
            )
            presentControllerImpl?(picker, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        },
        runTest: {
            LLMSettingsPresenter.shared.runConnectivityTest(from: hostController)
        },
        configureAgent: {
            promptAgentPort(context: context, hostController: hostController) {
                updateState { state in
                    var updated = state
                    updated.refreshToken &+= 1
                    return updated
                }
            }
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, SweetGramLLMSettingsArguments)) in
        _ = state
        let entries = sweetGramLLMSettingsEntries(presentationData: presentationData)
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("SweetGram AI"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    hostController = controller
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    return controller
}

private func presentProfileEditor(
    context: AccountContext,
    profileId: String?,
    present: @escaping (UIViewController) -> Void,
    onSave: @escaping () -> Void
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let existing = profileId.flatMap { id in LLMProfileManager.shared.listProfiles().first(where: { $0.id == id }) }

    let alert = UIAlertController(
        title: existing == nil ? "Add LLM API" : "Edit LLM API",
        message: "Base URL, API key (Keychain), model ID",
        preferredStyle: .alert
    )
    alert.addTextField { $0.placeholder = "Name"; $0.text = existing?.name ?? "My LLM" }
    alert.addTextField { $0.placeholder = "Base URL"; $0.text = existing?.baseURL ?? "https://api.openai.com" }
    alert.addTextField { $0.placeholder = "Model ID"; $0.text = existing?.model ?? "gpt-4o-mini" }
    alert.addTextField { $0.placeholder = "API Key"; $0.isSecureTextEntry = true }

    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Done, style: .default) { _ in
        let fields = alert.textFields ?? []
        let name = fields[safe: 0]?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseURL = fields[safe: 1]?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = fields[safe: 2]?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiKey = fields[safe: 3]?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, !baseURL.isEmpty, !model.isEmpty else { return }
        LLMSettingsPresenter.shared.saveManualProfile(id: profileId, name: name, baseURL: baseURL, model: model, apiKey: apiKey)
        onSave()
    })
    present(alert as UIViewController)
}

private func promptAgentPort(context: AccountContext, hostController: ViewController?, onSave: @escaping () -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let settings = SweetGramUserSettings.load()
    let alert = UIAlertController(title: "Agent Server Port", message: "Default 8787", preferredStyle: .alert)
    alert.addTextField { $0.text = "\(settings.agentServerPort)"; $0.keyboardType = .numberPad }
    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Done, style: .default) { _ in
        var updated = settings
        if let text = alert.textFields?.first?.text, let port = Int(text), port > 1024, port < 65535 {
            updated.agentServerPort = port
            updated.agentServerEnabled = true
            updated.save()
            AgentHTTPServer.shared.restart()
            onSave()
        }
    })
    context.sharedContext.applicationBindings.presentNativeController(alert)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public enum SweetGramSettingsHook {
    public static var isLLMSettingsAvailable: Bool {
        LLMSettingsPresenter.shared.isAvailable
    }

    public static func openLLMSettings(context: AccountContext, push: (ViewController) -> Void) {
        guard isLLMSettingsAvailable else { return }
        push(sweetGramLLMSettingsController(context: context))
    }
}
