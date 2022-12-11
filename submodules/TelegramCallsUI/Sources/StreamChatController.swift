import AccountContext
import Display
import Postbox
import ShareController
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit
import UndoUI

public final class StreamChatControllerImpl: ViewController, VoiceChatController {
    // MARK: - Properties

    public let call: PresentationGroupCall
    public weak var currentOverlayController: VoiceChatOverlayController?
    public weak var parentNavigationController: NavigationController?

    private let context: AccountContext

    public var onViewDidAppear: (() -> Void)?
    public var onViewDidDisappear: (() -> Void)?
    private var didAppearOnce: Bool = false
    private var isDismissed: Bool = false

    private let presentationData: PresentationData
    private let sharedContext: SharedAccountContext

    private let idleTimerExtensionDisposalbe = MetaDisposable()
    private let inviteLinksPromise = Promise<GroupCallInviteLinks?>(nil)

    private var validLayout: ContainerViewLayout?

    // MARK: - Nodes

    private var controllerNode: StreamChatControllerNode {
        displayNode as! StreamChatControllerNode
    }

    // MARK: - Life cycle

    public init(sharedContext: SharedAccountContext, accountContext: AccountContext, call: PresentationGroupCall) {
        self.sharedContext = sharedContext
        self.call = call
        self.presentationData = sharedContext.currentPresentationData.with { $0 }

        context = call.accountContext

        super.init(navigationBarPresentationData: nil)

        automaticallyControlPresentationContextLayout = false
        blocksBackgroundWhenInOverlay = true

        supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .all)

        statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Life cycle

    override public func loadDisplayNode() {
        displayNode = StreamChatControllerNode(controller: self, sharedContext: sharedContext, call: call)
        displayNodeDidLoad()
    }

    override public func displayNodeDidLoad() {
        super.displayNodeDidLoad()

        controllerNode.requestStatusBarStyleUpdated = { [weak self] statusBarStyle in
            self?.statusBar.updateStatusBarStyle(statusBarStyle, animated: true)
        }
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        isDismissed = false

        if !didAppearOnce {
            didAppearOnce = true

            controllerNode.animateIn()

            idleTimerExtensionDisposalbe.set(sharedContext.applicationBindings.pushIdleTimerExtension())
        }

        DispatchQueue.main.async {
            self.onViewDidAppear?()
        }
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        idleTimerExtensionDisposalbe.set(nil)

        DispatchQueue.main.async {
            self.didAppearOnce = false
            self.onViewDidDisappear?()
        }
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        validLayout = layout
        controllerNode.containerLayoutUpdated(layout, transition: transition)
    }

    // MARK: - Interface

    public func dismiss(closing: Bool, manual: Bool = false) {
        print("closing \(closing)")
        defer { dismiss() }
        
        controllerNode.saveDataIfNeeded()

        guard closing else { return }

        /*
         some updates for navigation controller
         */

        let _ = call.leave(terminateIfPossible: false)
    }

    override public func dismiss(completion: (() -> Void)? = nil) {
        guard !isDismissed else { return }

        isDismissed = true
        didAppearOnce = false

        controllerNode.animateOut { [weak self] in
            completion?()
            self?.dismiss(animated: false)
        }

        DispatchQueue.main.async {
            self.onViewDidDisappear?()
        }
    }

    // MARK: - Interface

    func presentShare() {
        let _ = (inviteLinksPromise.get()
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] inviteLinks in
            guard let strongSelf = self else {
                return
            }

            let _ = (strongSelf.context.engine.data.get(
                TelegramEngine.EngineData.Item.Peer.Peer(id: strongSelf.call.peerId),
                TelegramEngine.EngineData.Item.Peer.ExportedInvitation(id: strongSelf.call.peerId)
            )
            |> map { peer, exportedInvitation -> GroupCallInviteLinks? in
                if let inviteLinks = inviteLinks {
                    return inviteLinks
                } else if let peer = peer, let addressName = peer.addressName, !addressName.isEmpty {
                    return GroupCallInviteLinks(listenerLink: "https://t.me/\(addressName)?voicechat", speakerLink: nil)
                } else if let link = exportedInvitation?.link {
                    return GroupCallInviteLinks(listenerLink: link, speakerLink: nil)
                }
                return nil
            }
            |> deliverOnMainQueue).start(next: { [weak self] links in
                guard let self = self else { return }
                guard let links = links else { return }

                self.presentShare(links: links)
            })
        })
    }

    // MARK: - Private. Help

    private func presentShare(links inviteLinks: GroupCallInviteLinks) {
        let _ = (combineLatest(queue: .mainQueue(), call.account.postbox.loadedPeerWithId(call.peerId), call.state |> take(1))
        |> deliverOnMainQueue).start(next: { [weak self] peer, callState in
            if let strongSelf = self {
                var inviteLinks = inviteLinks

                if let peer = peer as? TelegramChannel, case .group = peer.info, !peer.flags.contains(.isGigagroup), !(peer.addressName ?? "").isEmpty, let defaultParticipantMuteState = callState.defaultParticipantMuteState {
                    let isMuted = defaultParticipantMuteState == .muted

                    if !isMuted {
                        inviteLinks = GroupCallInviteLinks(listenerLink: inviteLinks.listenerLink, speakerLink: nil)
                    }
                }

                let presentationData = strongSelf.sharedContext.currentPresentationData.with { $0 }

                var segmentedValues: [ShareControllerSegmentedValue]?
                segmentedValues = nil
                let shareController = ShareController(context: strongSelf.context, subject: .url(inviteLinks.listenerLink), segmentedValues: segmentedValues, forceTheme: defaultDarkPresentationTheme, forcedActionTitle: presentationData.strings.VoiceChat_CopyInviteLink)
                shareController.completed = { [weak self] peerIds in
                    if let strongSelf = self {
                        let _ = (strongSelf.context.engine.data.get(
                            EngineDataList(
                                peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)
                            )
                        )
                        |> deliverOnMainQueue).start(next: { [weak self] peerList in
                            if let strongSelf = self {
                                let peers = peerList.compactMap { $0 }
                                let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }

                                let text: String
                                var isSavedMessages = false
                                if peers.count == 1, let peer = peers.first {
                                    isSavedMessages = peer.id == strongSelf.context.account.peerId
                                    let peerName = peer.id == strongSelf.context.account.peerId ? presentationData.strings.DialogList_SavedMessages : peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                    text = presentationData.strings.VoiceChat_ForwardTooltip_Chat(peerName).string
                                } else if peers.count == 2, let firstPeer = peers.first, let secondPeer = peers.last {
                                    let firstPeerName = firstPeer.id == strongSelf.context.account.peerId ? presentationData.strings.DialogList_SavedMessages : firstPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                    let secondPeerName = secondPeer.id == strongSelf.context.account.peerId ? presentationData.strings.DialogList_SavedMessages : secondPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                    text = presentationData.strings.VoiceChat_ForwardTooltip_TwoChats(firstPeerName, secondPeerName).string
                                } else if let peer = peers.first {
                                    let peerName = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                    text = presentationData.strings.VoiceChat_ForwardTooltip_ManyChats(peerName, "\(peers.count - 1)").string
                                } else {
                                    text = ""
                                }

                                strongSelf.present(UndoOverlayController(presentationData: presentationData, content: .forward(savedMessages: isSavedMessages, text: text), elevatedLayout: false, animateInAsReplacement: true, action: { _ in return false }), in: .current)
                            }
                        })
                    }
                }
                shareController.actionCompleted = {
                    if let strongSelf = self {
                        let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }
                        strongSelf.present(UndoOverlayController(presentationData: presentationData, content: .linkCopied(text: presentationData.strings.VoiceChat_InviteLinkCopiedText), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .window(.root))
                    }
                }
                strongSelf.present(shareController, in: .window(.root))
            }
        })
    }
}
