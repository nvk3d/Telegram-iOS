import AsyncDisplayKit
import ChatTitleView
import Display
import TelegramPresentationData

private let separatorHeight = 1.0 / UIScreen.main.scale

private extension String {
    static let chatListAvatarContainerNode = ChatListItemNodeName.avatarContainerNode.rawValue
    static let chatListAvatarNode = ChatListItemNodeName.avatarNode.rawValue
    static let chatListMainContainerNode = ChatListItemNodeName.mainContentContainerNode.rawValue
    static let chatListOnlineNode = ChatListItemNodeName.onlineNode.rawValue
    static let chatListDateNode = ChatListItemNodeName.dateNode.rawValue
    static let chatListTitleNode = ChatListItemNodeName.titleNode.rawValue
    static let chatListTextNode = ChatListItemNodeName.textNode.rawValue
    static let chatListCredibilityNode = ChatListItemNodeName.credibilityIconView.rawValue
    static let chatListMutedIconNode = ChatListItemNodeName.mutedIconNode.rawValue
    static let chatListSeparatorNode = ChatListItemNodeName.separatorNode.rawValue

    static let chatTitleTextNode = ChatTitleViewName.titleTextNode.rawValue
    static let chatTitleActivityNode = ChatTitleViewName.activityNode.rawValue
}

final class ChatListContextAnimationNode: ASDisplayNode {
    // MARK: - Children

    enum State {
        // MARK: - Cases

        case chatListItem
        case navigationBarPreview
    }

    // MARK: - Properties

    private let presentationData: PresentationData
    private let navigationPresentationData: NavigationBarPresentationData

    private var state: State = .chatListItem

    private var size: CGSize = .zero
    private var safeInsets: UIEdgeInsets = .zero
    private var scale: CGFloat = 0.0

    // MARK: - Views & Layers

    private var chatListItemSnapshot: UIView?
    private var chatTitleViewSnapshot: UIView?

    private var chatListItemSeparatorLayer: CALayer?

    // MARK: - Nodes

    private let backgroundNode: NavigationBackgroundNode

    // MARK: - Init

    init(presentationData: PresentationData) {
        self.presentationData = presentationData
        self.navigationPresentationData = NavigationBarPresentationData(presentationData: presentationData)

        self.backgroundNode = NavigationBackgroundNode(color: navigationPresentationData.theme.backgroundColor)

        super.init()

        self.addSubnode(self.backgroundNode)
    }

    // MARK: - Life cycle

    func updateLayout(size: CGSize, scale: CGFloat, safeInsets: UIEdgeInsets, animated: Bool) {
        self.size = size
        self.scale = scale
        self.safeInsets = safeInsets

        let springDuration: Double = 0.52
        let springDamping: CGFloat = 110.0

        let shortTransition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        let mediumTransition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.3, curve: .easeInOut) : .immediate
        let springTransition: ContainedViewLayoutTransition = animated ? .animated(duration: springDuration, curve: .customSpring(damping: springDamping, initialVelocity: 0.0)) : .immediate

        backgroundNode.updateColor(color: navigationPresentationData.theme.backgroundColor, transition: mediumTransition)
        let backgroundFrame = CGRect(origin: .zero, size: size)
        springTransition.updateFrame(node: backgroundNode, frame: backgroundFrame)
        backgroundNode.update(size: backgroundFrame.size, transition: springTransition)

        guard let chatListItemSnapshot = chatListItemSnapshot else { return }
        guard let chatTitleViewSnapshot = chatTitleViewSnapshot else { return }

        switch state {
        case .chatListItem:
            break
//            shortTransition.updateTransformScale(node: avatarContainerNode, scale: 0.3)
//            shortTransition.updateAlpha(node: avatarContainerNode, alpha: 0.0)
            //shortTransition.updateAlpha(node: onlineNode, alpha: 0.0)

        case .navigationBarPreview:
            springTransition.updateTransformScale(node: self, scale: scale)

            find(for: .chatListAvatarContainerNode, in: chatListItemSnapshot.layer).flatMap { avatarContainerLayer in
                avatarContainerLayer.rasterizationScale = UIScreenScale
                shortTransition.updateTransformScale(layer: avatarContainerLayer, scale: 0.3)
                shortTransition.updateAlpha(layer: avatarContainerLayer, alpha: 0.0)
            }

            let rightButtonSize = CGSize(width: 37.0, height: 37.0)
            let rightButtonFrame = CGRect(
                origin: CGPoint(x: chatTitleViewSnapshot.frame.maxX + 11.0, y: (size.height - rightButtonSize.height) / 2.0),
                size: rightButtonSize
            )
            find(for: .chatListAvatarNode, in: chatListItemSnapshot.layer).flatMap { avatarLayer in
                if let avatarSnapshotLayer = avatarLayer.snapshotContentTree() {
                    let baseWidth = avatarLayer.bounds.width

                    avatarSnapshotLayer.rasterizationScale = UIScreenScale
                    avatarSnapshotLayer.position = CGPoint(x: rightButtonFrame.midX, y: rightButtonFrame.midY)

                    let scale = rightButtonSize.width / baseWidth
                    let transition: ContainedViewLayoutTransition = .immediate
                    transition.updateTransformScale(layer: avatarSnapshotLayer, scale: scale)

                    view.layer.addSublayer(avatarSnapshotLayer)

                    avatarSnapshotLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false)
                    avatarSnapshotLayer.animateScale(from: 0.3, to: scale, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false)
                }
            }

            find(for: .chatListDateNode, in: chatListItemSnapshot.layer).flatMap { dateLayer in
                dateLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            }

            let clCredibilityIconLayer = find(for: .chatListCredibilityNode, in: chatListItemSnapshot.layer)

            let clTitleLayer = find(for: .chatListTitleNode, in: chatListItemSnapshot.layer)
            let ctTitleLayer = find(for: .chatTitleTextNode, in: chatTitleViewSnapshot.layer)

            let titleBeginFrame: CGRect = clTitleLayer?.frame ?? .zero
            let titleFinalFrame: CGRect = ctTitleLayer?.frame ?? .zero
            let titlesWidthDifference = titleFinalFrame.width - titleBeginFrame.width

            let clTitleBeginPosition = CGPoint(x: titleBeginFrame.midX, y: titleBeginFrame.midY)
            let clTitleFinalPosition = layer.convert(layer.convert(CGPoint(x: titleFinalFrame.midX - titlesWidthDifference / 2.0, y: titleFinalFrame.midY), from: ctTitleLayer?.superlayer), to: clTitleLayer?.superlayer)

            let ctTitleBeginPosition = layer.convert(layer.convert(CGPoint(x: titleBeginFrame.midX + titlesWidthDifference / 2.0, y: titleBeginFrame.midY), from: clTitleLayer?.superlayer), to: ctTitleLayer?.superlayer)
            let ctTitleFinalPosition = CGPoint(x: titleFinalFrame.midX, y: titleFinalFrame.midY)

            clTitleLayer.flatMap { titleLayer in
                titleLayer.animateSpring(from: NSValue(cgPoint: clTitleBeginPosition), to: NSValue(cgPoint: clTitleFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping)
                titleLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            }

            ctTitleLayer.flatMap { titleLayer in
                titleLayer.animateSpring(from: NSValue(cgPoint: ctTitleBeginPosition), to: NSValue(cgPoint: ctTitleFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping)
                titleLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            }

            let anchorTitleFinalPosition = layer.convert(layer.convert(CGPoint(x: titleFinalFrame.midX, y: titleFinalFrame.midY), from: ctTitleLayer?.superlayer), to: clTitleLayer?.superlayer)
            let credibilityBeginPosition = clCredibilityIconLayer?.position ?? .zero
            let credibilityFinalPosition = CGPoint(x: anchorTitleFinalPosition.x + titleBeginFrame.width / 2.0 + 6.0, y: anchorTitleFinalPosition.y)

            clCredibilityIconLayer.flatMap { credibilityLayer in
                credibilityLayer.animateSpring(from: NSValue(cgPoint: credibilityBeginPosition), to: NSValue(cgPoint: credibilityFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, removeOnCompletion: false)
            }

            find(for: .chatListMutedIconNode, in: chatListItemSnapshot.layer).flatMap { mutedIconLayer in
                let position: CGPoint
                if let credibilityLayer = clCredibilityIconLayer {
                    position = CGPoint(x: credibilityFinalPosition.x + credibilityLayer.bounds.width / 2.0 + 6.0, y: anchorTitleFinalPosition.y)
                } else {
                    position = CGPoint(x: anchorTitleFinalPosition.x + titleBeginFrame.width / 2.0 + 6.0 + mutedIconLayer.bounds.width / 2.0, y: anchorTitleFinalPosition.y)
                }
                mutedIconLayer.animateSpring(from: NSValue(cgPoint: mutedIconLayer.position), to: NSValue(cgPoint: position), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, removeOnCompletion: false)
                mutedIconLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false)
            }

            let clTextNode = find(for: .chatListTextNode, in: chatListItemSnapshot.layer)
            clTextNode.flatMap { textLayer in
                textLayer.rasterizationScale = UIScreenScale

                textLayer.animateScale(from: 1.0, to: 0.8, duration: 0.25, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false)
                textLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false)
            }

            chatListItemSeparatorLayer.flatMap { separatorLayer in
                let position = CGPoint(x: size.width / 2.0, y: size.height)
                let bounds = CGRect(origin: .zero, size: CGSize(width: size.width, height: separatorHeight))
                springTransition.updatePosition(layer: separatorLayer, position: position)
                springTransition.updateBounds(layer: separatorLayer, bounds: bounds)
            }

            find(for: .chatTitleActivityNode, in: chatTitleViewSnapshot.layer).flatMap { activityLayer in
                activityLayer.rasterizationScale = UIScreenScale

                activityLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2, delay: 0.1, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false)
                activityLayer.animateScale(from: 0.9, to: 1.0, duration: 0.1, delay: 0.1, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false)

                let beginPosition = CGPoint(x: clTitleBeginPosition.x, y: activityLayer.position.y)
                let finalPosition = activityLayer.position
                activityLayer.animateSpring(from: NSValue(cgPoint: beginPosition), to: NSValue(cgPoint: finalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping)
            }

            let manualUpdateIdentifiers: [String] = [
                .chatListAvatarContainerNode,
                .chatListMainContainerNode,
                .chatListDateNode,
                .chatListTitleNode,
                .chatListTextNode,
                .chatListCredibilityNode,
                .chatListMutedIconNode,

                .chatTitleTextNode,
                .chatTitleActivityNode
            ]
            find(for: .chatListMainContainerNode, in: chatListItemSnapshot.layer).flatMap { containerLayer in
                for sublayer in containerLayer.sublayers ?? [] {
                    if let name = sublayer.name, manualUpdateIdentifiers.contains(name) {
                        continue
                    }
                    sublayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
                }
            }
            find(for: .chatListOnlineNode, in: chatListItemSnapshot.layer).flatMap { onlineLayer in
                onlineLayer.rasterizationScale = UIScreenScale

                onlineLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.1, removeOnCompletion: false)
                onlineLayer.animateScale(from: 1.0, to: 0.3, duration: 0.1, removeOnCompletion: false)
            }
        }
    }

    // MARK: - Interface

    func updateState(_ state: State, sourceNode: ASDisplayNode, controller: ViewController, size: CGSize, animated: Bool) {
        guard self.state != state else { return }
        self.state = state

        chatListItemSnapshot?.removeFromSuperview()
        chatTitleViewSnapshot?.removeFromSuperview()
        chatListItemSeparatorLayer?.removeFromSuperlayer()

        chatListItemSnapshot = sourceNode.view.snapshotContentTree()
        chatListItemSeparatorLayer = find(for: "separatorNode", in: sourceNode.supernode?.layer ?? sourceNode.layer)?.snapshotContentTree()
        _ = controller.navigationBar?.titleView?.snapshotView(afterScreenUpdates: true) // wait until renders
        chatTitleViewSnapshot = (controller.navigationBar?.titleView as? ChatTitleView)?.snapshotContentTree()

        chatListItemSnapshot.flatMap { view.addSubview($0) }
        chatTitleViewSnapshot.flatMap { view.addSubview($0) }
        chatListItemSeparatorLayer.flatMap { view.layer.addSublayer($0) }

        self.size = size
        updateLayout(size: size, scale: scale, safeInsets: safeInsets, animated: animated)
    }

    // MARK: - Private. Help

    private func find(for identifier: String, in layer: CALayer) -> CALayer? {
        if layer.name == identifier {
            return layer
        }

        for sublayer in layer.sublayers ?? [] {
            guard let founded = find(for: identifier, in: sublayer) else { continue }
            return founded
        }
        return nil
    }
}
