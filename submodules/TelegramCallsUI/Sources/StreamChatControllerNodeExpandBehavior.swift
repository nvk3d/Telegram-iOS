import AsyncDisplayKit
import Display

final class StreamChatControllerNodeExpandBehavior: StreamChatControllerNodeBehavior {
    // MARK: - Properties

    var requestDismiss: (() -> Void)?
    var requestStatusBarStyleUpdated: ((StatusBarStyle) -> Void)?

    private var layout: ContainerViewLayout?

    private var isLayoutUpdating: Bool = false
    private var videoAspectUpdate: ((ContainerViewLayout) -> Void)?

    private var panGestureInProgress: Bool = false
    private var videoNodeOffset: CGPoint = .zero

    private var isPanelsHidden: Bool = true

    private var expandTopPanelHeight: CGFloat {
        (layout?.statusBarHeight ?? 0.0) + 44.0
    }
    private var expandBottomPanelHeight: CGFloat {
        (layout?.intrinsicInsets.bottom ?? 0.0) + 44.0
    }

    // MARK: - Nodes

    let nodes: StreamChatControllerNodeBehaviorNodes

    private var dimNode: ASDisplayNode { nodes.dimNode }
    private var contentContainerNode: ASDisplayNode { nodes.contentContainerNode }

    private var topPanelNode: ASDisplayNode { nodes.topPanelNode }
    private var expandTopPanelNode: ASDisplayNode { nodes.expandTopPanelNode }

    private var optionsButton: VoiceChatHeaderButton { nodes.optionsButton }
    private var titleNode: StreamChatTitleNode { nodes.titleNode }
    private var pictureInPictureButton: VoiceChatHeaderButton { nodes.pictureInPictureButton }

    private var expandCloseButton: ASButtonNode { nodes.expandCloseButton }
    private var expandTopTitleNode: ASTextNode { nodes.expandTopTitleNode }
    private var expandPictureInPictureButton: ASButtonNode { nodes.expandPictureInPictureButton }

    private var videoNode: StreamChatVideoNode { nodes.videoNode }
    private var watchingNode: StreamChatWatchingNode { nodes.watchingNode }

    private var bottomPanelNode: StreamChatBottomPanelNode { nodes.bottomPanelNode }

    private var expandBottomPanelNode: ASDisplayNode { nodes.expandBottomPanelNode }

    private var expandShareButton: ASButtonNode { nodes.expandShareButton }
    private var expandBottomTitleNode: ASTextNode { nodes.expandBottomTitleNode }
    private var expandBottomSubtitleNode: ASTextNode { nodes.expandBottomSubtitleNode }
    private var expandExpandButton: ASButtonNode { nodes.expandExpandButton }

    // MARK: - Init

    init(
        nodes: StreamChatControllerNodeBehaviorNodes,
        requestDismiss: (() -> Void)?,
        requestStatusBarStyleUpdated: ((StatusBarStyle) -> Void)?
    ) {
        self.nodes = nodes
        self.requestDismiss = requestDismiss
        self.requestStatusBarStyleUpdated = requestStatusBarStyleUpdated
    }

    // MARK: - Life cycle

    func didLoad(animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .slide) : .immediate

        transition.updateAlpha(node: expandTopPanelNode, alpha: 1.0)
        transition.updateAlpha(node: expandBottomPanelNode, alpha: 1.0)

        transition.updateAlpha(node: topPanelNode, alpha: 0.0)
        transition.updateAlpha(node: watchingNode, alpha: 0.0)
        transition.updateAlpha(node: bottomPanelNode, alpha: 0.0)

        transition.updateBackgroundColor(node: contentContainerNode, color: fullscreenBackgroundColor)
        videoNode.updateCornerRadius(0.0, transition: transition)

        requestStatusBarStyleUpdated?(.White)
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.layout = layout
        isLayoutUpdating = true

        transition.updateFrame(node: dimNode, frame: CGRect(origin: .zero, size: layout.size))

        let videoSize = calculateVideoSize(in: layout)

        let topPanelHeight = topPanelHeight
        let watchingHeight: CGFloat = 150.0
        let bottomPanelMargin: CGFloat = 10.0
        let bottomPanelHeight: CGFloat = 56.0 + 30.0 // buttonSize + additionalMargin

        let contentContainerHeight: CGFloat = layout.size.height
        let contentContainerFrame = CGRect(
            origin: CGPoint(x: 0.0, y: layout.size.height - contentContainerHeight),
            size: CGSize(width: layout.size.width, height: contentContainerHeight)
        )
        transition.updateFrame(node: contentContainerNode, frame: contentContainerFrame) { [weak self] _ in
            self?.isLayoutUpdating = false
            self?.completeUpdates()
        }
        transition.updateCornerRadius(node: contentContainerNode, cornerRadius: 0.0)

        let topPanelFrame = CGRect(origin: CGPoint(x: layout.safeInsets.left, y: layout.statusBarHeight ?? 0.0), size: CGSize(width: contentContainerFrame.width - layout.safeInsets.left - layout.safeInsets.right, height: topPanelHeight))
        transition.updateFrame(node: topPanelNode, frame: topPanelFrame)

        let headerButtonSize = CGSize(width: 28.0, height: 28.0)
        transition.updateFrame(node: optionsButton, frame: CGRect(
            origin: CGPoint(x: 20.0, y: 18.0),
            size: headerButtonSize
        ))
        transition.updateFrame(node: pictureInPictureButton, frame: CGRect(
            origin: CGPoint(x: topPanelFrame.width - headerButtonSize.width - 20.0, y: 18.0),
            size: headerButtonSize
        ))

        let titleFrame = CGRect(
            origin: CGPoint(x: 0.0, y: 10.0),
            size: CGSize(width: topPanelFrame.width, height: topPanelHeight - 20.0)
        )
        transition.updateFrame(node: titleNode, frame: titleFrame)

        let titleLayout = layout.withUpdatedSize(titleFrame.size)
        titleNode.containerLayoutUpdated(titleLayout, transition: transition)

        let videoFrame = CGRect(
            x: (layout.size.width - videoSize.width) / 2.0,
            y: (layout.size.height - videoSize.height) / 2.0 + videoNodeOffset.y,
            width: videoSize.width,
            height: videoSize.height
        )
        transition.updateFrame(node: videoNode, frame: videoFrame)

        let videoLayout = layout.withUpdatedSize(videoFrame.size)
        videoNode.containerLayoutUpdated(videoLayout, transition: transition)

        let watchingFrame = CGRect(x: layout.safeInsets.left, y: videoFrame.maxY, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right, height: watchingHeight)
        transition.updateFrame(node: watchingNode, frame: watchingFrame)

        let watchingLayout = layout.withUpdatedSize(watchingFrame.size)
        watchingNode.containerLayoutUpdated(watchingLayout, transition: transition)

        let bottomPanelWidth = layout.size.width - layout.safeInsets.left - layout.safeInsets.right
        let bottomPanelFrame = CGRect(
            origin: CGPoint(x: layout.safeInsets.left, y: watchingFrame.maxY + bottomPanelMargin),
            size: CGSize(width: bottomPanelWidth, height: bottomPanelHeight)
        )
        transition.updateFrame(node: bottomPanelNode, frame: bottomPanelFrame)

        let bottomPanelLayout = layout
            .withUpdatedIntrinsicInsets(.zero)
            .withUpdatedSize(bottomPanelFrame.size)
        bottomPanelNode.containerLayoutUpdated(bottomPanelLayout, transition: transition)

        // expand
        let expandTopPanelY: CGFloat = isPanelsHidden ? -expandBottomPanelHeight : 0.0
        let expandTopPanelFrame = CGRect(origin: CGPoint(x: 0.0, y: expandTopPanelY), size: CGSize(width: layout.size.width, height: expandTopPanelHeight))
        transition.updateFrame(node: expandTopPanelNode, frame: expandTopPanelFrame)

        let expandButtonHeight: CGFloat = 44.0

        let expandCloseButtonSize = expandCloseButton.measure(CGSize(width: 100.0, height: 44.0))
        let expandCloseButtonFrame = CGRect(
            x: layout.safeInsets.left + 16.0,
            y: layout.statusBarHeight ?? 0.0,
            width: expandCloseButtonSize.width,
            height: 44.0
        )
        transition.updateFrame(node: expandCloseButton, frame: expandCloseButtonFrame)

        let expandTitleSize = expandTopTitleNode.measure(CGSize(width: layout.size.width, height: 44.0))
        let expandTitleFrame = CGRect(
            x: (layout.size.width - expandTitleSize.width) / 2.0,
            y: (layout.statusBarHeight ?? 0.0) + (44.0 - expandTitleSize.height) / 2.0,
            width: expandTitleSize.width,
            height: expandTitleSize.height
        )
        transition.updateFrame(node: expandTopTitleNode, frame: expandTitleFrame)

        let expandPictureInPictureFrame = CGRect(
            x: expandTopPanelFrame.width - layout.safeInsets.right - 44.0 - 16.0,
            y: layout.statusBarHeight ?? 0.0,
            width: 44.0,
            height: expandButtonHeight
        )
        transition.updateFrame(node: expandPictureInPictureButton, frame: expandPictureInPictureFrame)

        let expandBottomHeight = expandBottomPanelHeight
        let expandBottomPanelY: CGFloat = isPanelsHidden ? layout.size.height : layout.size.height - expandBottomHeight
        let expandBottomPanelFrame = CGRect(x: 0.0, y: expandBottomPanelY, width: layout.size.width, height: expandBottomHeight)
        transition.updateFrame(node: expandBottomPanelNode, frame: expandBottomPanelFrame)

        let expandShareFrame = CGRect(
            origin: CGPoint(x: layout.safeInsets.left + 16.0, y: 0.0),
            size: CGSize(width: 44.0, height: expandButtonHeight)
        )
        transition.updateFrame(node: expandShareButton, frame: expandShareFrame)

        let expandBottomTitleSize = expandBottomTitleNode.measure(CGSize(width: layout.size.width, height: 44.0))
        let expandBottomSubtitleSize = expandBottomSubtitleNode.measure(CGSize(width: layout.size.width, height: 44.0))
        let titlesSize = CGSize(width: layout.size.width, height: expandTitleSize.height + expandBottomSubtitleSize.height)

        let expandBottomTitleFrame = CGRect(
            x: (layout.size.width - expandBottomTitleSize.width) / 2.0,
            y: (44.0 - titlesSize.height) / 2.0,
            width: expandBottomTitleSize.width,
            height: expandBottomTitleSize.height
        )
        transition.updateFrame(node: expandBottomTitleNode, frame: expandBottomTitleFrame)

        let expandBottomSubtitleFrame = CGRect(
            x: (layout.size.width - expandBottomSubtitleSize.width) / 2.0,
            y: expandBottomTitleFrame.maxY,
            width: expandBottomSubtitleSize.width,
            height: expandBottomSubtitleSize.height
        )
        transition.updateFrame(node: expandBottomSubtitleNode, frame: expandBottomSubtitleFrame)

        let expandExpandFrame = CGRect(
            origin: CGPoint(x: layout.size.width - layout.safeInsets.right - 44.0 - 16.0, y: 0.0),
            size: CGSize(width: 44.0, height: expandButtonHeight)
        )
        transition.updateFrame(node: expandExpandButton, frame: expandExpandFrame)
    }

    // MARK: - Interface

    func animateIn() {
        guard let layout = layout else { return }

        requestStatusBarStyleUpdated?(.White)

        ContainedViewLayoutTransition.immediate.updateAlpha(node: contentContainerNode, alpha: 0.0)

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.4, curve: .easeInOut)
        transition.updateAlpha(node: contentContainerNode, alpha: 1.0)

        if !isPanelsHidden {
            setPanelsHidden(isPanelsHidden, transition: transition)
        }

        containerLayoutUpdated(layout, transition: transition)
        dimNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3) { [weak self] _ in
            guard let self = self else { return }
            self.videoNode.updateVideoAfterAnimatingIn()
        }
    }

    func animateOut(_ completion: (() -> Void)?) {
        dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)

        isPanelsHidden = true

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.4, curve: .easeInOut)
        setPanelsHidden(isPanelsHidden, transition: transition)

        transition.updateAlpha(node: contentContainerNode, alpha: 0.0) { [weak self] _ in
            guard let self = self else { return }

            self.videoNodeOffset = .zero
            self.layout.flatMap { self.containerLayoutUpdated($0, transition: .immediate) }
            self.videoNode.updateVideoAfterAnimatingOut()

            completion?()
        }
    }

    func tapGestureAction(_ sender: UITapGestureRecognizer) {
        isPanelsHidden.toggle()

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .slide)
        setPanelsHidden(isPanelsHidden, transition: transition)
    }

    func panGestureAction(_ sender: UIPanGestureRecognizer) {
        let translation = sender.translation(in: sender.view)
        sender.setTranslation(.zero, in: sender.view)

        videoNodeOffset.y += translation.y

        switch sender.state {
        case .began, .changed:
            panGestureInProgress = true
            layout.flatMap { containerLayoutUpdated($0, transition: .immediate) }

        case .cancelled, .ended, .failed:
            let velocity = sender.velocity(in: sender.view)
            let progress = abs(videoNodeOffset.y / videoNode.frame.height)

            if velocity.y > 300.0 || progress >= 0.5 {
                videoNodeOffset = CGPoint(x: 0.0, y: videoNodeOffset.y < 0.0 ? -videoNode.frame.height : videoNode.frame.height)
                requestDismiss?()
            } else {
                let duration = min(0.3, videoNodeOffset.y / max(1.0, velocity.y))
                videoNodeOffset = .zero

                let transition: ContainedViewLayoutTransition = .animated(duration: duration, curve: .easeInOut)
                layout.flatMap { containerLayoutUpdated($0, transition: transition) }
            }

        default:
            break
        }
    }

    func videoAspectUpdated() {
        guard !panGestureInProgress else { return }

        if isLayoutUpdating {
            videoAspectUpdate = { [weak self] layout in
                self?.containerLayoutUpdated(layout, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        } else {
            layout.flatMap { containerLayoutUpdated($0, transition: .animated(duration: 0.3, curve: .easeInOut)) }
        }
    }

    // MARK: - Private. Updates

    private func completeUpdates() {
        guard let layout = layout else { return }

        if let videoAspectUpdate = videoAspectUpdate {
            self.videoAspectUpdate = nil
            videoAspectUpdate(layout)
        }
    }

    // MARK: - Private. Help

    private func calculateVideoSize(in layout: ContainerViewLayout) -> CGSize {
        let videoAspect = videoNode.getAspect()

        let videoWidth: CGFloat
        let videoHeight: CGFloat

        switch layout.orientation {
        case .portrait:
            videoWidth = layout.size.width
            videoHeight = videoWidth / videoAspect

        case .landscape:
            videoHeight = layout.size.height
            videoWidth = videoHeight * videoAspect
        }

        return CGSize(width: videoWidth, height: videoHeight)
    }

    private func setPanelsHidden(_ hidden: Bool, transition: ContainedViewLayoutTransition) {
        guard let layout = layout else { return }
        containerLayoutUpdated(layout, transition: transition)
    }
}
