import AccountContext
import AsyncDisplayKit
import AvatarNode
import AVKit
import DirectionalPanGesture
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramVoip
import UIKit
import UIKitRuntimeUtils

func setAccessibilityIdentifiers(for node: ASDisplayNode) {
    let mirror = Mirror(reflecting: node)
    for children in mirror.children {
        guard let label = children.label else { continue }
        guard let node = mirror.descendant(label) as? ASDisplayNode else { continue }
        node.isAccessibilityElement = true
        node.accessibilityIdentifier = children.label
    }
}

struct StreamChatControllerNodeBehaviorNodes {
    // MARK: - Nodes

    let dimNode: ASDisplayNode
    let contentContainerNode: ASDisplayNode

    let topPanelNode: ASDisplayNode
    let expandTopPanelNode: ASDisplayNode

    let optionsButton: VoiceChatHeaderButton
    let titleNode: StreamChatTitleNode
    let pictureInPictureButton: VoiceChatHeaderButton

    let expandCloseButton: ASButtonNode
    let expandTopTitleNode: ASTextNode
    let expandPictureInPictureButton: ASButtonNode

    let videoNode: StreamChatVideoNode
    let watchingNode: StreamChatWatchingNode

    let bottomPanelNode: StreamChatBottomPanelNode

    let expandBottomPanelNode: ASDisplayNode

    let expandShareButton: ASButtonNode
    let expandBottomTitleNode: ASTextNode
    let expandBottomSubtitleNode: ASTextNode
    let expandExpandButton: ASButtonNode
}

protocol StreamChatControllerNodeBehavior: AnyObject {
    // MARK: - Nodes

    var requestStatusBarStyleUpdated: ((StatusBarStyle) -> Void)? { get set }
    var nodes: StreamChatControllerNodeBehaviorNodes { get }

    // MARK: - Life cycle

    func didLoad(animated: Bool)
    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition)

    // MARK: - Interface

    func animateIn()
    func animateOut(_ completion: (() -> Void)?)
    func tapGestureAction()
    func videoAspectUpdated()
}

private final class Throttler {
    // MARK: - Properties

    private let queue: Queue

    private var item: DispatchWorkItem = DispatchWorkItem(block: {})
    private var previousRun: Date = .distantPast
    private var maxInterval: TimeInterval

    // MARK: - Init

    init(maxInterval: TimeInterval, queue: Queue = .mainQueue()) {
        self.maxInterval = maxInterval
        self.queue = queue
    }

    // MARK: - Interface

    func throttle(block: @escaping () -> ()) {
        item.cancel()
        item = DispatchWorkItem { [weak self] in
            self?.previousRun = Date()
            block()
        }

        let delay = maxInterval
        queue.queue.asyncAfter(deadline: .now() + Double(delay), execute: item)
    }

    func cancel() {
        item.cancel()
    }
}

final class StreamChatControllerNode: ViewControllerTracingNode, UIGestureRecognizerDelegate {
    // MARK: - Children

    enum Mode: Equatable {
        // MARK: - Cases

        case online
        case offline
    }

    // MARK: - Properties

    var requestStatusBarStyleUpdated: ((StatusBarStyle) -> Void)?

    private let nodeContext: StreamChatContext

    private let sharedContext: SharedAccountContext
    private let context: AccountContext
    private let call: PresentationGroupCall
    private let presentationData: PresentationData
    private var darkTheme: PresentationTheme

    private var layout: ContainerViewLayout?

    private weak var controller: StreamChatControllerImpl?

    private var isBeingDismissed: Bool = false
    private let isPictureInPictureSupported: Bool

    private let numberFormatter: NumberFormatter

    private var mode: Mode = .offline
    private var lastBuffer: OngoingGroupCallContext.VideoFrameData.Buffer?
    private let bufferQueue: Queue = Queue(queue: DispatchQueue(label: "ph.Telegram.StreamBufferQueue", qos: .userInitiated, autoreleaseFrequency: .workItem))

    private var currentBufferUpdating: Bool = false
    private let bufferUpdatingThrottler = Throttler(maxInterval: 0.2)

    private var peer: Peer?
    private var peerPreviewImageFetched: Bool = false
    private var peerPreviewImageExist: Bool = false
    private var peerAvatarImageExist: Bool = false

    private var callStateDisposable: Disposable?
    private var bufferDisposable: Disposable?
    private var peerViewDisposable: Disposable?
    private var peerImageDisposable: Disposable?
    private var networkDisposable: Disposable?
    private var stateNetworkDisposable: Disposable?
    private var stateMembersDisposable: Disposable?
    private var pictureInPictureVisible: Disposable?

    // MARK: - Behavior

    private lazy var behavior: StreamChatControllerNodeBehavior = StreamChatControllerNodePreviewBehavior(nodes: StreamChatControllerNodeBehaviorNodes(
        dimNode: dimNode,
        contentContainerNode: contentContainerNode,
        topPanelNode: topPanelNode,
        expandTopPanelNode: expandTopPanelNode,
        optionsButton: optionsButton,
        titleNode: titleNode,
        pictureInPictureButton: pictureInPictureButton,
        expandCloseButton: expandCloseButton,
        expandTopTitleNode: expandTopTitleNode,
        expandPictureInPictureButton: expandPictureInPictureButton,
        videoNode: videoNode,
        watchingNode: watchingNode,
        bottomPanelNode: bottomPanelNode,
        expandBottomPanelNode: expandBottomPanelNode,
        expandShareButton: expandShareButton,
        expandBottomTitleNode: expandBottomTitleNode,
        expandBottomSubtitleNode: expandBottomSubtitleNode,
        expandExpandButton: expandExpandButton
    ), requestStatusBarStyleUpdated: { [weak self] statusBarStyle in self?.requestStatusBarStyleUpdated?(statusBarStyle) })

    // MARK: - Nodes

    private let dimNode: ASDisplayNode
    private let contentContainerNode: ASDisplayNode

    private let topPanelNode: ASDisplayNode

    private let optionsButton: VoiceChatHeaderButton
    private let titleNode: StreamChatTitleNode
    private let pictureInPictureButton: VoiceChatHeaderButton

    private let videoNode: StreamChatVideoNode
    private let watchingNode: StreamChatWatchingNode

    private let bottomPanelNode: StreamChatBottomPanelNode

    private let expandTopPanelNode: ASDisplayNode

    private let expandCloseButton: ASButtonNode
    private let expandTopTitleNode: ASTextNode
    private let expandPictureInPictureButton: ASButtonNode

    private let expandBottomPanelNode: ASDisplayNode

    private let expandShareButton: ASButtonNode
    private let expandBottomTitleNode: ASTextNode
    private let expandBottomSubtitleNode: ASTextNode
    private let expandExpandButton: ASButtonNode

    // MARK: - Init

    init(controller: StreamChatControllerImpl, sharedContext: SharedAccountContext, call: PresentationGroupCall) {
        self.nodeContext = StreamChatContext()
        self.controller = controller
        self.sharedContext = sharedContext
        self.context = call.accountContext
        self.call = call

        let presentationData = sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData

        darkTheme = defaultDarkPresentationTheme

        numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSeparator = ","

        dimNode = ASDisplayNode()
        dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.5)

        contentContainerNode = ASDisplayNode()
        contentContainerNode.cornerRadius = 12.0
        contentContainerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentContainerNode.backgroundColor = panelBackgroundColor

        topPanelNode = ASDisplayNode()
        topPanelNode.clipsToBounds = false
        topPanelNode.backgroundColor = .clear

        expandTopPanelNode = ASDisplayNode()
        expandTopPanelNode.backgroundColor = fullscreenBackgroundColor.withAlphaComponent(0.5)

        expandCloseButton = ASButtonNode()
        expandCloseButton.setTitle("Close", with: Font.regular(17.0), with: .white, for: .normal)

        expandTopTitleNode = ASTextNode()
        expandTopTitleNode.displaysAsynchronously = false
        expandTopTitleNode.maximumNumberOfLines = 1
        expandTopTitleNode.truncationMode = .byTruncatingTail
        expandTopTitleNode.isOpaque = false

        expandPictureInPictureButton = ASButtonNode()
        expandPictureInPictureButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Media Gallery/PictureInPictureButton"), color: .white), for: .normal)

        optionsButton = VoiceChatHeaderButton(context: context)
        optionsButton.alpha = 0.0
        optionsButton.setContent(.more(optionsCircleImage(dark: false)))

        titleNode = StreamChatTitleNode(theme: presentationData.theme)

        if #available(iOSApplicationExtension 15.0, iOS 15.0, *), AVPictureInPictureController.isPictureInPictureSupported() {
            isPictureInPictureSupported = true
        } else {
            isPictureInPictureSupported = false
        }

        pictureInPictureButton = VoiceChatHeaderButton(context: context)
        pictureInPictureButton.setContent(.image(generateTintedImageCircle(image: UIImage(bundleImageName: "Media Gallery/PictureInPictureButtonFilled"), color: .white, backgroundColor: secondaryPanelBackgroundColor, scale: 1.0)))

        let presentationCall = call as! PresentationGroupCallImpl
        videoNode = StreamChatVideoNode(input: presentationCall.video(endpointId: "unified"), theme: presentationData.theme)
        watchingNode = StreamChatWatchingNode(theme: presentationData.theme)

        bottomPanelNode = StreamChatBottomPanelNode(presentationData: presentationData)
        bottomPanelNode.clipsToBounds = false
        bottomPanelNode.backgroundColor = .clear

        expandBottomPanelNode = ASDisplayNode()
        expandBottomPanelNode.backgroundColor = fullscreenBackgroundColor.withAlphaComponent(0.5)

        expandShareButton = ASButtonNode()
        expandShareButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionForward"), color: .white), for: .normal)

        expandBottomTitleNode = ASTextNode()
        expandBottomTitleNode.displaysAsynchronously = false
        expandBottomTitleNode.maximumNumberOfLines = 2
        expandBottomTitleNode.truncationMode = .byTruncatingTail
        expandBottomTitleNode.isOpaque = false

        expandBottomSubtitleNode = ASTextNode()
        expandBottomSubtitleNode.displaysAsynchronously = false
        expandBottomSubtitleNode.maximumNumberOfLines = 2
        expandBottomSubtitleNode.truncationMode = .byTruncatingTail
        expandBottomSubtitleNode.isOpaque = false

        expandExpandButton = ASButtonNode()
        expandExpandButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Media Gallery/Minimize"), color: .white), for: .normal)

        super.init()

        setupNodes()
        setupCallUpdates()

        setAccessibilityIdentifiers(for: self)
    }

    deinit {
        callStateDisposable?.dispose()
        bufferDisposable?.dispose()
        peerViewDisposable?.dispose()
        peerImageDisposable?.dispose()
        networkDisposable?.dispose()
        stateNetworkDisposable?.dispose()
        stateMembersDisposable?.dispose()
        pictureInPictureVisible?.dispose()
    }

    // MARK: - Life cycle

    override func didLoad() {
        super.didLoad()

        view.disablesInteractiveTransitionGestureRecognizer = true
        view.disablesInteractiveModalDismiss = true

        dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapGesture(_:))))

        let contentTapGesture = UITapGestureRecognizer(target: self, action: #selector(contentTapGesture(_:)))
        contentTapGesture.delegate = self
        contentContainerNode.view.addGestureRecognizer(contentTapGesture)

//        let panRecognizer = DirectionalPanGestureRecognizer(target: self, action: #selector(panGesture(_:)))
//        panRecognizer.delegate = self
//        panRecognizer.delaysTouchesBegan = false
//        panRecognizer.cancelsTouchesInView = true
//        view.addGestureRecognizer(panRecognizer)

        watchingNode.setTitle("0", transition: .immediate)
        watchingNode.setSubtitle("watching", transition: .immediate)

        behavior.didLoad(animated: false)
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard !isBeingDismissed else { return }

        let prevLayout = self.layout
        self.layout = layout

        switch layout.orientation {
        case .portrait:
            guard behavior is StreamChatControllerNodeExpandBehavior else { break }
            behavior = StreamChatControllerNodePreviewBehavior(nodes: behavior.nodes, requestStatusBarStyleUpdated: behavior.requestStatusBarStyleUpdated)
            behavior.didLoad(animated: prevLayout != nil)

        case .landscape:
            guard behavior is StreamChatControllerNodePreviewBehavior else { break }
            behavior = StreamChatControllerNodeExpandBehavior(nodes: behavior.nodes, requestStatusBarStyleUpdated: behavior.requestStatusBarStyleUpdated)
            behavior.didLoad(animated: prevLayout != nil)
        }

        behavior.containerLayoutUpdated(layout, transition: transition)
    }

    // MARK: - Life cycle. Gestures

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let contentTapGesture = gestureRecognizer as? UITapGestureRecognizer, contentTapGesture.view === contentContainerNode.view {
            return behavior is StreamChatControllerNodeExpandBehavior
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer {
            return true
        }
        return false
    }

    // MARK: - Interface

    func animateIn() {
        guard var layout = layout else { return }

        isBeingDismissed = false

        if layout.size != UIScreen.main.bounds.size {
            layout = layout
                .withUpdatedIntrinsicInsets(UIApplication.shared.keyWindow?.safeAreaInsets ?? layout.intrinsicInsets)
                .withUpdatedSize(UIScreen.main.bounds.size)
        }

        containerLayoutUpdated(layout, transition: .immediate)

        videoNode.deactivatePictureInPicture(smoothCorners: behavior is StreamChatControllerNodePreviewBehavior)
        behavior.animateIn()
    }

    func animateOut(completion: (() -> Void)?) {
        guard !isBeingDismissed else { return }
        guard layout != nil else { return }

        isBeingDismissed = true

        behavior.animateOut(completion)
    }

    func saveDataIfNeeded() {
        guard let peer = peer else { return }

        let nodeContext = nodeContext
        bufferQueue.async { // note: strong reference for successfully saving buffer
            guard let buffer = self.lastBuffer else { return }
            nodeContext.save(buffer, peer: peer)
        }
    }

    // MARK: - Private. Setup

    private func setupNodes() {
        addSubnode(dimNode)
        addSubnode(contentContainerNode)

        videoNode.requestAspectUpdated = { [weak self] in
            self?.behavior.videoAspectUpdated()
        }
        videoNode.requestBackControllerForPictureInPicture = { [weak self] in
            guard let self = self else { return }
            let _ = self.call.accountContext.sharedContext.mainWindow?.inCallNavigate?()
        }
        videoNode.requestClosePictureInPicture = { [weak self] in
            guard let self = self else { return }
            self.controller?.dismiss(closing: true)
        }
        videoNode.requestSmoothCornersForPictureInPicture = { [weak self] in
            guard let self = self else { return false }
            return self.behavior is StreamChatControllerNodePreviewBehavior
        }
        contentContainerNode.addSubnode(videoNode)

        contentContainerNode.addSubnode(topPanelNode)
        topPanelNode.addSubnode(titleNode)

        optionsButton.addTarget(self, action: #selector(optionsButtonAction(_:)), forControlEvents: .touchUpInside)
        topPanelNode.addSubnode(optionsButton)

        pictureInPictureButton.addTarget(self, action: #selector(pictureInPictureButtonAction(_:)), forControlEvents: .touchUpInside)
        pictureInPictureButton.layer.opacity = isPictureInPictureSupported ? 1.0 : 0.0
        topPanelNode.addSubnode(pictureInPictureButton)

        contentContainerNode.addSubnode(watchingNode)
        contentContainerNode.addSubnode(bottomPanelNode)

        bottomPanelNode.shareTapped = { [weak self] in
            self?.controller?.presentShare()
        }

        bottomPanelNode.expandTapped = { [weak self] in
            guard let self = self else { return }
            self.sharedContext.applicationBindings.forceOrientation(.landscapeRight)
        }

        bottomPanelNode.leaveTapped = { [weak self] in
            self?.controller?.dismiss(closing: true)
        }

        // expand
        addSubnode(expandTopPanelNode)

        expandCloseButton.addTarget(self, action: #selector(expandCloseButtonAction(_:)), forControlEvents: .touchUpInside)
        expandTopPanelNode.addSubnode(expandCloseButton)

        expandTopTitleNode.attributedText = NSAttributedString(string: "Live Stream", font: Font.bold(17.0), textColor: .white)
        expandTopPanelNode.addSubnode(expandTopTitleNode)

        expandPictureInPictureButton.addTarget(self, action: #selector(expandPictureInPictureButtonAction(_:)), forControlEvents: .touchUpInside)
        expandTopPanelNode.addSubnode(expandPictureInPictureButton)

        addSubnode(expandBottomPanelNode)

        expandShareButton.addTarget(self, action: #selector(expandShareButtonAction(_:)), forControlEvents: .touchUpInside)
        expandBottomPanelNode.addSubnode(expandShareButton)

        expandBottomPanelNode.addSubnode(expandBottomTitleNode)
        expandBottomPanelNode.addSubnode(expandBottomSubtitleNode)

        expandExpandButton.addTarget(self, action: #selector(expandExpandButtonAction(_:)), forControlEvents: .touchUpInside)
        expandBottomPanelNode.addSubnode(expandExpandButton)
    }

    private func setupCallUpdates() {
        callStateDisposable = call.state.start { [weak self] state in
            guard let self = self else { return }
            self.optionsButton.alpha = state.adminIds.contains(self.call.account.peerId) ? 1.0 : 0.0
        }

        let titleSignal: Signal<String?, NoError> = call.state
        |> map { state -> String? in
            state.title
        }
        peerViewDisposable = combineLatest(queue: .mainQueue(), context.account.viewTracker.peerView(call.peerId), titleSignal).start(next: { [weak self] view, title in
            guard let self = self else { return }
            guard let peer = peerViewMainPeer(view) else { return }

            self.peer = peer
            let enginePeer = EnginePeer(peer)

            let title: String = title ?? enginePeer.displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)
            self.titleNode.setTitle(title, transition: .immediate)
            self.expandBottomTitleNode.attributedText = NSAttributedString(string: title, font: Font.bold(15.0), textColor: .white)

            if !self.peerPreviewImageFetched {
                self.peerPreviewImageFetched = true

                self.nodeContext.fetchPreview(for: peer) { [weak self] image in
                    guard let self = self else { return }

                    self.peerPreviewImageFetched = image != nil
                    self.peerPreviewImageExist = image != nil
                    image.flatMap { self.videoNode.imageUpdated($0, aspected: true, transition: .immediate) }

                    self.behavior.videoAspectUpdated()
                }
            }

            if !self.peerAvatarImageExist, !self.peerPreviewImageExist {
                let videoSize = self.videoNode.frame.size
                let imageSize = CGSize(width: videoSize.width * UIScreenScale, height: videoSize.height * UIScreenScale)
                self.peerImageDisposable = (peerAvatarCompleteImage(account: self.call.account, peer: enginePeer, size: imageSize, round: false) |> deliverOnMainQueue).start(next: { [weak self] image in
                    guard let self = self else { return }
                    guard !self.peerAvatarImageExist else { return }
                    guard !self.peerPreviewImageExist else { return }

                    self.peerAvatarImageExist = image != nil
                    self.videoNode.imageUpdated(image, transition: .immediate)
                })
            }
        })

        let presentationCall = call as! PresentationGroupCallImpl
        let stateNetworkStatus: Signal<PresentationGroupCallState.NetworkState, NoError> = call.state
        |> map { state -> PresentationGroupCallState.NetworkState in
            state.networkState
        }
        stateNetworkDisposable = combineLatest(queue: .mainQueue(), call.account.networkState, stateNetworkStatus).start(next: { [weak self] accountNetworkState, networkState in
            guard let self = self else { return }

            if self.bufferDisposable == nil, networkState == .connected {
                self.updateVideoSignalListers(presentationCall)
            }

            self.updateMode()
        })

        stateMembersDisposable = call.members.start(next: { [weak self] members in
            guard let self = self else { return }

            let membersCount = max(0, members?.totalCount ?? 0)
            let title = self.numberFormatter.string(from: NSNumber(value: membersCount))
            self.watchingNode.setTitle(title ?? "\(membersCount)", transition: .animated(duration: 0.4, curve: .spring))

            self.expandBottomSubtitleNode.attributedText = NSAttributedString(string: "\(title ?? "0") viewers", font: Font.regular(14.0), textColor: .white)
            self.layout.flatMap { self.containerLayoutUpdated($0, transition: .immediate) }
        })

        pictureInPictureVisible = (call.accountContext.sharedContext.applicationBindings.applicationInForeground |> deliverOnMainQueue).start { [weak self] inForeground in
            guard let self = self else { return }

            if inForeground, !self.isBeingDismissed {
                Queue.mainQueue().after(0.5) { [weak self] in
                    guard let self = self else { return }
                    self.videoNode.deactivatePictureInPicture(smoothCorners: self.behavior is StreamChatControllerNodePreviewBehavior)
                }
            }
        }
    }

    // MARK: - Private. Actions

    @objc
    private func dimTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard case .ended = recognizer.state else { return }

        videoNode.activatePictureInPicture { [weak self] in
            self?.controller?.dismiss(closing: false, manual: true)
        }
    }

    @objc
    private func contentTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard case .ended = recognizer.state else { return }
        behavior.tapGestureAction()
    }

    @objc
    private func panGesture(_ recognizer: UIPanGestureRecognizer) {

    }

    @objc
    private func optionsButtonAction(_ button: VoiceChatHeaderButton) {
        button.play()
    }

    @objc
    private func pictureInPictureButtonAction(_ button: VoiceChatHeaderButton) {
        button.play()

        if videoNode.isPictureInPictureActive {
            videoNode.deactivatePictureInPicture(smoothCorners: behavior is StreamChatControllerNodePreviewBehavior)
        } else {
            videoNode.activatePictureInPicture(smoothCorners: behavior is StreamChatControllerNodePreviewBehavior) { [weak self] in
                self?.controller?.dismiss(closing: false, manual: true)
            }
        }
    }

    @objc
    private func expandPictureInPictureButtonAction(_ button: ASButtonNode) {
        videoNode.activatePictureInPicture { [weak self] in
            self?.controller?.dismiss(closing: false, manual: true)
        }
    }

    @objc
    private func expandCloseButtonAction(_ button: ASButtonNode) {
        controller?.dismiss(closing: true)
    }

    @objc
    private func expandShareButtonAction(_ button: ASButtonNode) {
        controller?.presentShare()
    }

    @objc
    private func expandExpandButtonAction(_ button: ASButtonNode) {
        sharedContext.applicationBindings.forceOrientation(.portrait)
    }

    // MARK: - Updates

    private func updateMode() {
        let mode: Mode = currentBufferUpdating ? .online : .offline

        guard self.mode != mode else { return }
        self.mode = mode

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .slide)

        switch mode {
        case .online:
            titleNode.setMode(.online, transition: transition)
            videoNode.setMode(.online, transition: transition)

        case .offline:
            titleNode.setMode(.offline, transition: transition)
            videoNode.setMode(.offline, transition: transition)
        }
    }

    private func updateVideoSignalListers(_ call: PresentationGroupCallImpl) {
        guard let signal = call.video(endpointId: "unified") else { return }

        bufferDisposable = signal.start { [weak self] frameData in
            guard let self = self else { return }

            let bufferUpdatingOld = self.currentBufferUpdating
            self.currentBufferUpdating = true

            if bufferUpdatingOld != self.currentBufferUpdating {
                Queue.mainQueue().async { self.updateMode() }
            }

            self.bufferQueue.async { self.lastBuffer = frameData.buffer }

            self.bufferUpdatingThrottler.throttle { [weak self] in
                guard let self = self else { return }

                let bufferUpdatingOld = self.currentBufferUpdating
                self.currentBufferUpdating = false

                if bufferUpdatingOld != self.currentBufferUpdating {
                    self.updateMode()
                }
            }
        }

        videoNode.videoUpdated(signal, transition: .immediate)
    }
}
