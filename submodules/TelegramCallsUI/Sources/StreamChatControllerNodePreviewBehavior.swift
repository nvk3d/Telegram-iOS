import AsyncDisplayKit
import Display

final class StreamChatControllerNodePreviewBehavior: StreamChatControllerNodeBehavior {
    // MARK: - Properties

    var requestStatusBarStyleUpdated: ((StatusBarStyle) -> Void)?

    private var layout: ContainerViewLayout?

    private var isLayoutUpdating: Bool = false
    private var requestedLayout: (ContainerViewLayout, ContainedViewLayoutTransition)?
    private var videoAspectUpdate: ((ContainerViewLayout) -> Void)?

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
    private var expandExpandButton: ASButtonNode { nodes.expandExpandButton }

    // MARK: - Init

    init(nodes: StreamChatControllerNodeBehaviorNodes, requestStatusBarStyleUpdated: ((StatusBarStyle) -> Void)?) {
        self.nodes = nodes
        self.requestStatusBarStyleUpdated = requestStatusBarStyleUpdated
    }

    // MARK: - Life cycle

    func didLoad(animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .slide) : .immediate

        transition.updateAlpha(node: expandTopPanelNode, alpha: 0.0)
        transition.updateAlpha(node: expandBottomPanelNode, alpha: 0.0)

        transition.updateAlpha(node: topPanelNode, alpha: 1.0)
        transition.updateAlpha(node: watchingNode, alpha: 1.0)
        transition.updateAlpha(node: bottomPanelNode, alpha: 1.0)

        transition.updateBackgroundColor(node: contentContainerNode, color: panelBackgroundColor)
        videoNode.updateCornerRadius(12.0, transition: transition)

        requestStatusBarStyleUpdated?(.Ignore)
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard !isLayoutUpdating else { requestedLayout = (layout, transition); return }

        self.layout = layout
        isLayoutUpdating = true

        transition.updateFrame(node: dimNode, frame: CGRect(origin: .zero, size: layout.size))

        let videoSideMargin: CGFloat = 16.0

        let topPanelHeight = topPanelHeight
        let videoSize = calculateVideoSize(in: layout, videoSideMargin: videoSideMargin)
        let watchingWidth: CGFloat = layout.size.width - videoSideMargin * 2.0
        let watchingHeight: CGFloat = 150.0
        let bottomPanelMargin: CGFloat = 10.0
        let bottomPanelHeight: CGFloat = 56.0 + 30.0 // buttonSize + additionalMargin

        let contentContainerHeight: CGFloat = topPanelHeight + watchingHeight + videoSize.height + bottomPanelMargin + bottomPanelHeight + layout.intrinsicInsets.bottom
        let contentContainerFrame = CGRect(
            origin: CGPoint(x: 0.0, y: layout.size.height - contentContainerHeight),
            size: CGSize(width: layout.size.width, height: contentContainerHeight)
        )
        transition.updateFrame(node: contentContainerNode, frame: contentContainerFrame) { [weak self] _ in
            self?.isLayoutUpdating = false
            self?.completeUpdates()
        }
        transition.updateCornerRadius(node: contentContainerNode, cornerRadius: 12.0)

        let topPanelFrame = CGRect(origin: .zero, size: CGSize(width: contentContainerFrame.width, height: topPanelHeight))
        transition.updateFrame(node: topPanelNode, frame: topPanelFrame)

        let headerButtonSize = CGSize(width: 28.0, height: 28.0)
        transition.updateFrame(node: optionsButton, frame: CGRect(
            origin: CGPoint(x: layout.intrinsicInsets.left + 20.0, y: 18.0),
            size: headerButtonSize
        ))
        transition.updateFrame(node: pictureInPictureButton, frame: CGRect(
            origin: CGPoint(x: layout.size.width - layout.intrinsicInsets.right - headerButtonSize.width - 20.0, y: 18.0),
            size: headerButtonSize
        ))

        let titleFrame = CGRect(
            origin: CGPoint(x: layout.intrinsicInsets.left, y: 10.0),
            size: CGSize(width: layout.size.width - layout.intrinsicInsets.left - layout.intrinsicInsets.right, height: topPanelHeight - 20.0)
        )
        transition.updateFrame(node: titleNode, frame: titleFrame)

        let titleLayout = layout.withUpdatedSize(titleFrame.size)
        titleNode.containerLayoutUpdated(titleLayout, transition: transition)

        let videoFrame = CGRect(x: (layout.size.width - videoSize.width) / 2.0, y: topPanelFrame.maxY, width: videoSize.width, height: videoSize.height)
        transition.updateFrame(node: videoNode, frame: videoFrame)

        let videoLayout = layout.withUpdatedSize(videoFrame.size)
        videoNode.containerLayoutUpdated(videoLayout, transition: transition)

        let watchingFrame = CGRect(x: videoSideMargin, y: videoFrame.maxY, width: watchingWidth, height: watchingHeight)
        transition.updateFrame(node: watchingNode, frame: watchingFrame)

        let watchingLayout = layout.withUpdatedSize(watchingFrame.size)
        watchingNode.containerLayoutUpdated(watchingLayout, transition: transition)

        let bottomPanelWidth = layout.size.width - layout.intrinsicInsets.left - layout.intrinsicInsets.right
        let bottomPanelFrame = CGRect(
            origin: CGPoint(x: layout.intrinsicInsets.left, y: contentContainerHeight - bottomPanelHeight - layout.intrinsicInsets.bottom - bottomPanelMargin),
            size: CGSize(width: bottomPanelWidth, height: bottomPanelHeight)
        )
        transition.updateFrame(node: bottomPanelNode, frame: bottomPanelFrame)

        let bottomPanelLayout = layout
            .withUpdatedIntrinsicInsets(.zero)
            .withUpdatedSize(bottomPanelFrame.size)
        bottomPanelNode.containerLayoutUpdated(bottomPanelLayout, transition: transition)

        // expand
        let expandTopPanelHeight = (layout.statusBarHeight ?? 0.0) + 44.0
        let expandTopPanelFrame = CGRect(origin: CGPoint(x: 0.0, y: -expandTopPanelHeight), size: CGSize(width: layout.size.width, height: expandTopPanelHeight))
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

        let expandBottomHeight: CGFloat = layout.intrinsicInsets.bottom + 44.0
        let expandBottomPanelFrame = CGRect(x: 0.0, y: layout.size.height, width: layout.size.width, height: expandBottomHeight)
        transition.updateFrame(node: expandBottomPanelNode, frame: expandBottomPanelFrame)

        let expandShareFrame = CGRect(
            origin: CGPoint(x: layout.safeInsets.left + 16.0, y: 0.0),
            size: CGSize(width: 44.0, height: expandButtonHeight)
        )
        transition.updateFrame(node: expandShareButton, frame: expandShareFrame)

        let expandBottomTitleSize = expandBottomTitleNode.measure(CGSize(width: layout.size.width, height: 44.0))
        let expandBottomTitleFrame = CGRect(
            x: (layout.size.width - expandBottomTitleSize.width) / 2.0,
            y: (44.0 - expandBottomTitleSize.height) / 2.0,
            width: expandBottomTitleSize.width,
            height: expandBottomTitleSize.height
        )
        transition.updateFrame(node: expandBottomTitleNode, frame: expandBottomTitleFrame)

        let expandExpandFrame = CGRect(
            origin: CGPoint(x: layout.size.width - layout.safeInsets.right - 44.0 - 16.0, y: 0.0),
            size: CGSize(width: 44.0, height: expandButtonHeight)
        )
        transition.updateFrame(node: expandExpandButton, frame: expandExpandFrame)
    }

    // MARK: - Interface

    func animateIn() {
        guard let layout = layout else { return }

        requestStatusBarStyleUpdated?(.Ignore)

        ContainedViewLayoutTransition.immediate.updateAlpha(node: contentContainerNode, alpha: 1.0)

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.4, curve: .spring)
        contentContainerNode.frame.origin.y = layout.size.height

        containerLayoutUpdated(layout, transition: transition)
        dimNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
    }

    func animateOut(_ completion: (() -> Void)?) {
        guard let layout = layout else { return }
        dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.4, curve: .spring)
        transition.updateFrame(node: contentContainerNode, frame: CGRect(origin: CGPoint(x: contentContainerNode.frame.minX, y: layout.size.height), size: contentContainerNode.frame.size)) { _ in
            completion?()
        }
    }

    func tapGestureAction() {}

    func videoAspectUpdated() {
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

        if let requestedLayout = requestedLayout {
            self.requestedLayout = nil
            containerLayoutUpdated(requestedLayout.0, transition: requestedLayout.1)
        }

        if let videoAspectUpdate = videoAspectUpdate {
            self.videoAspectUpdate = nil
            videoAspectUpdate(layout)
        }
    }

    // MARK: - Private. Help

    private func calculateVideoSize(in layout: ContainerViewLayout, videoSideMargin: CGFloat) -> CGSize {
        let videoAspect: CGFloat = videoNode.getAspect()

        let videoWidth: CGFloat
        let videoHeight: CGFloat

        if videoAspect >= 1.0 {
            videoWidth = layout.size.width - videoSideMargin * 2.0
            videoHeight = videoWidth / videoAspect
        } else {
            videoHeight = layout.size.width - videoSideMargin * 2.0
            videoWidth = videoHeight * videoAspect
        }

        return CGSize(width: videoWidth, height: videoHeight)
    }
}
