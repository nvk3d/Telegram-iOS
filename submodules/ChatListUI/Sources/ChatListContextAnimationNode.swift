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

    static let localAvatarSnapshot = "localAvatarSnapshot"
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

    private let simpleBackgroundNode: ASDisplayNode
    private let backgroundNode: NavigationBackgroundNode

    // MARK: - Init

    init(presentationData: PresentationData) {
        self.presentationData = presentationData
        self.navigationPresentationData = NavigationBarPresentationData(presentationData: presentationData)

        self.simpleBackgroundNode = ASDisplayNode()
        self.backgroundNode = NavigationBackgroundNode(color: navigationPresentationData.theme.backgroundColor)

        super.init()

        self.addSubnode(self.simpleBackgroundNode)
        self.addSubnode(self.backgroundNode)
    }

    // MARK: - Life cycle

    func updateLayout(size: CGSize, scale: CGFloat, safeInsets: UIEdgeInsets, animated: Bool) {
        let previousSize = self.size
        self.size = size
        self.scale = scale
        self.safeInsets = safeInsets

        let springDuration: Double = 0.52
        let springDamping: CGFloat = 110.0

        let shortTransition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        let mediumTransition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.3, curve: .easeInOut) : .immediate
        let springTransition: ContainedViewLayoutTransition = animated ? .animated(duration: springDuration, curve: .customSpring(damping: springDamping, initialVelocity: 0.0)) : .immediate

        simpleBackgroundNode.backgroundColor = presentationData.theme.chatList.itemBackgroundColor
        springTransition.updateFrame(node: simpleBackgroundNode, frame: CGRect(origin: .zero, size: size))

        backgroundNode.updateColor(color: navigationPresentationData.theme.backgroundColor, transition: mediumTransition)
        let backgroundFrame = CGRect(origin: .zero, size: size)
        springTransition.updateFrame(node: backgroundNode, frame: backgroundFrame)
        backgroundNode.update(size: backgroundFrame.size, transition: springTransition)

        guard let chatListItemSnapshot = chatListItemSnapshot else { return }
        guard let chatTitleViewSnapshot = chatTitleViewSnapshot else { return }

        switch state {
        case .chatListItem:
            shortTransition.updateAlpha(node: backgroundNode, alpha: 0.0)
            shortTransition.updateAlpha(node: simpleBackgroundNode, alpha: 1.0)

            springTransition.updateTransformScale(node: self, scale: scale)

            find(for: .chatListAvatarContainerNode, in: chatListItemSnapshot.layer).flatMap { avatarContainerLayer in
                avatarContainerLayer.rasterizationScale = UIScreenScale
                animateScale(avatarContainerLayer, from: 0.3, to: 1.0, duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, animated: animated)
                animateAlpha(avatarContainerLayer, from: 0.0, to: 1.0, duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, animated: animated)
            }

            let rightButtonSize = CGSize(width: 37.0, height: 37.0)
            let rightButtonFrame = CGRect(
                origin: CGPoint(x: chatTitleViewSnapshot.frame.maxX + 11.0, y: (previousSize.height - rightButtonSize.height) / 2.0),
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

                    avatarSnapshotLayer.name = .localAvatarSnapshot
                    view.layer.addSublayer(avatarSnapshotLayer)

                    animateAlpha(avatarSnapshotLayer, from: 1.0, to: 0.0, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, animated: animated)
                    animateScale(avatarSnapshotLayer, from: scale, to: 0.3, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, animated: animated)
                }
            }

            let clCredibilityIconLayer = find(for: .chatListCredibilityNode, in: chatListItemSnapshot.layer)

            let clTitleLayer = find(for: .chatListTitleNode, in: chatListItemSnapshot.layer)
            let ctTitleLayer = find(for: .chatTitleTextNode, in: chatTitleViewSnapshot.layer)

            let titleBeginFrame: CGRect = clTitleLayer?.frame ?? .zero
            let titleFinalFrame: CGRect = ctTitleLayer?.frame ?? .zero
            let titlesWidthDifference = titleFinalFrame.width - titleBeginFrame.width

            let clTitleBeginPosition = layer.convert(layer.convert(CGPoint(x: titleFinalFrame.midX - titlesWidthDifference / 2.0, y: titleFinalFrame.midY), from: ctTitleLayer?.superlayer), to: clTitleLayer?.superlayer)
            let clTitleFinalPosition = CGPoint(x: titleBeginFrame.midX, y: titleBeginFrame.midY)

            let ctTitleBeginPosition = CGPoint(x: titleFinalFrame.midX, y: titleFinalFrame.midY)
            let ctTitleFinalPosition = layer.convert(layer.convert(CGPoint(x: titleBeginFrame.midX + titlesWidthDifference / 2.0, y: titleBeginFrame.midY), from: clTitleLayer?.superlayer), to: ctTitleLayer?.superlayer)

            clTitleLayer.flatMap { titleLayer in
                animateSpring(titleLayer, from: NSValue(cgPoint: clTitleBeginPosition), to: NSValue(cgPoint: clTitleFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
                animateAlpha(titleLayer, from: 0.0, to: 1.0, duration: 0.2, animated: animated)
            }

            ctTitleLayer.flatMap { titleLayer in
                animateSpring(titleLayer, from: NSValue(cgPoint: ctTitleBeginPosition), to: NSValue(cgPoint: ctTitleFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
                animateAlpha(titleLayer, from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, animated: animated)
            }

            let anchorTitleFinalPosition = layer.convert(layer.convert(CGPoint(x: titleFinalFrame.midX, y: titleFinalFrame.midY), from: ctTitleLayer?.superlayer), to: clTitleLayer?.superlayer)
            let credibilityBeginPosition = CGPoint(x: anchorTitleFinalPosition.x + titleBeginFrame.width / 2.0 + 6.0, y: anchorTitleFinalPosition.y)
            let credibilityFinalPosition = clCredibilityIconLayer?.position ?? .zero

            clCredibilityIconLayer.flatMap { credibilityLayer in
                animateSpring(credibilityLayer, from: NSValue(cgPoint: credibilityBeginPosition), to: NSValue(cgPoint: credibilityFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
            }

            find(for: .chatListMutedIconNode, in: chatListItemSnapshot.layer).flatMap { mutedIconLayer in
                let position: CGPoint
                if let credibilityLayer = clCredibilityIconLayer {
                    position = CGPoint(x: credibilityFinalPosition.x + credibilityLayer.bounds.width / 2.0 + 6.0, y: anchorTitleFinalPosition.y)
                } else {
                    position = CGPoint(x: anchorTitleFinalPosition.x + titleBeginFrame.width / 2.0 + 6.0 + mutedIconLayer.bounds.width / 2.0, y: anchorTitleFinalPosition.y)
                }
                animateSpring(mutedIconLayer, from: NSValue(cgPoint: position), to: NSValue(cgPoint: mutedIconLayer.position), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
                animateAlpha(mutedIconLayer, from: 0.0, to: 1.0, duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, animated: animated)
            }

            let titlePositionDifference = clTitleBeginPosition.x - clTitleFinalPosition.x

            find(for: .chatListDateNode, in: chatListItemSnapshot.layer).flatMap { dateLayer in
                animateAlpha(dateLayer, from: 0.0, to: 1.0, duration: 0.2, delay: 0.1, animated: animated)

                let beginPosition = CGPoint(x: dateLayer.position.x + titlePositionDifference, y: dateLayer.position.y)
                let finalPosition = dateLayer.position
                animateSpring(dateLayer, from: NSValue(cgPoint: beginPosition), to: NSValue(cgPoint: finalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
            }

            let clTextNode = find(for: .chatListTextNode, in: chatListItemSnapshot.layer)
            clTextNode.flatMap { textLayer in
                textLayer.rasterizationScale = UIScreenScale

                animateAlpha(textLayer, from: 0.0, to: 1.0, duration: 0.25, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, animated: animated)

                let beginPosition = CGPoint(x: textLayer.position.x + titlePositionDifference, y: textLayer.position.y)
                let finalPosition = textLayer.position
                animateSpring(textLayer, from: NSValue(cgPoint: beginPosition), to: NSValue(cgPoint: finalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
            }

            chatListItemSeparatorLayer.flatMap { separatorLayer in
                let beginPosition = CGPoint(x: size.width / 2.0, y: previousSize.height)
                let finalPosition = separatorLayer.position

                let beginBounds = CGRect(origin: .zero, size: CGSize(width: size.width, height: separatorHeight))
                let finalBounds = separatorLayer.bounds

                animateSpring(separatorLayer, from: NSValue(cgPoint: beginPosition), to: NSValue(cgPoint: finalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
                animateSpring(separatorLayer, from: NSValue(cgRect: beginBounds), to: NSValue(cgRect: finalBounds), keyPath: "bounds", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
            }

            find(for: .chatTitleActivityNode, in: chatTitleViewSnapshot.layer).flatMap { activityLayer in
                activityLayer.rasterizationScale = UIScreenScale

                animateAlpha(activityLayer, from: 1.0, to: 0.0, duration: 0.1, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false, animated: animated)
                animateScale(activityLayer, from: 1.0, to: 0.9, duration: 0.1, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false, animated: animated)

                let beginPosition = activityLayer.position
                let finalPosition = CGPoint(x: clTitleBeginPosition.x, y: activityLayer.position.y)
                animateSpring(activityLayer, from: NSValue(cgPoint: beginPosition), to: NSValue(cgPoint: finalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, removeOnCompletion: false, animated: animated)
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
                    animateAlpha(sublayer, from: 0.0, to: 1.0, duration: 0.2, delay: 0.1, removeOnCompletion: false, animated: animated)
                }
            }
            find(for: .chatListOnlineNode, in: chatListItemSnapshot.layer).flatMap { onlineLayer in
                onlineLayer.rasterizationScale = UIScreenScale

                animateAlpha(onlineLayer, from: 0.0, to: 1.0, duration: 0.1, delay: 0.15, animated: animated)
                animateScale(onlineLayer, from: 0.3, to: 1.0, duration: 0.1, delay: 0.15, animated: animated)
            }

        case .navigationBarPreview:
            shortTransition.updateAlpha(node: backgroundNode, alpha: 1.0)
            shortTransition.updateAlpha(node: simpleBackgroundNode, alpha: 0.0)

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

                    avatarSnapshotLayer.name = .localAvatarSnapshot
                    view.layer.addSublayer(avatarSnapshotLayer)

                    animateAlpha(avatarSnapshotLayer, from: 0.0, to: 1.0, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, animated: animated)
                    animateScale(avatarSnapshotLayer, from: 0.3, to: scale, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, animated: animated)
                }
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
                animateSpring(titleLayer, from: NSValue(cgPoint: clTitleBeginPosition), to: NSValue(cgPoint: clTitleFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
                animateAlpha(titleLayer, from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, animated: animated)
            }

            ctTitleLayer.flatMap { titleLayer in
                animateSpring(titleLayer, from: NSValue(cgPoint: ctTitleBeginPosition), to: NSValue(cgPoint: ctTitleFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
                animateAlpha(titleLayer, from: 0.0, to: 1.0, duration: 0.2, animated: animated)
            }

            let anchorTitleFinalPosition = layer.convert(layer.convert(CGPoint(x: titleFinalFrame.midX, y: titleFinalFrame.midY), from: ctTitleLayer?.superlayer), to: clTitleLayer?.superlayer)
            let credibilityBeginPosition = clCredibilityIconLayer?.position ?? .zero
            let credibilityFinalPosition = CGPoint(x: anchorTitleFinalPosition.x + titleBeginFrame.width / 2.0 + 6.0, y: anchorTitleFinalPosition.y)

            clCredibilityIconLayer.flatMap { credibilityLayer in
                animateSpring(credibilityLayer, from: NSValue(cgPoint: credibilityBeginPosition), to: NSValue(cgPoint: credibilityFinalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, removeOnCompletion: false, animated: animated)
            }

            find(for: .chatListMutedIconNode, in: chatListItemSnapshot.layer).flatMap { mutedIconLayer in
                let position: CGPoint
                if let credibilityLayer = clCredibilityIconLayer {
                    position = CGPoint(x: credibilityFinalPosition.x + credibilityLayer.bounds.width / 2.0 + 6.0, y: anchorTitleFinalPosition.y)
                } else {
                    position = CGPoint(x: anchorTitleFinalPosition.x + titleBeginFrame.width / 2.0 + 6.0 + mutedIconLayer.bounds.width / 2.0, y: anchorTitleFinalPosition.y)
                }
                animateSpring(mutedIconLayer, from: NSValue(cgPoint: mutedIconLayer.position), to: NSValue(cgPoint: position), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, removeOnCompletion: false, animated: animated)
                animateAlpha(mutedIconLayer, from: 1.0, to: 0.0, duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false, animated: animated)
            }

            let titlePositionDifference = clTitleFinalPosition.x - clTitleBeginPosition.x

            find(for: .chatListDateNode, in: chatListItemSnapshot.layer).flatMap { dateLayer in
                animateAlpha(dateLayer, from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, animated: animated)

                let beginPosition = dateLayer.position
                let finalPosition = CGPoint(x: beginPosition.x + titlePositionDifference, y: dateLayer.position.y)
                animateSpring(dateLayer, from: NSValue(cgPoint: beginPosition), to: NSValue(cgPoint: finalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
            }

            let clTextNode = find(for: .chatListTextNode, in: chatListItemSnapshot.layer)
            clTextNode.flatMap { textLayer in
                textLayer.rasterizationScale = UIScreenScale

                animateAlpha(textLayer, from: 1.0, to: 0.0, duration: 0.25, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false, animated: animated)

                let beginPosition = textLayer.position
                let finalPosition = CGPoint(x: beginPosition.x + titlePositionDifference, y: textLayer.position.y)
                animateSpring(textLayer, from: NSValue(cgPoint: beginPosition), to: NSValue(cgPoint: finalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
            }

            chatListItemSeparatorLayer.flatMap { separatorLayer in
                let position = CGPoint(x: size.width / 2.0, y: size.height)
                let bounds = CGRect(origin: .zero, size: CGSize(width: size.width, height: separatorHeight))
                springTransition.updatePosition(layer: separatorLayer, position: position)
                springTransition.updateBounds(layer: separatorLayer, bounds: bounds)
            }

            find(for: .chatTitleActivityNode, in: chatTitleViewSnapshot.layer).flatMap { activityLayer in
                activityLayer.rasterizationScale = UIScreenScale

                animateAlpha(activityLayer, from: 0.0, to: 1.0, duration: 0.2, delay: 0.1, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false, animated: animated)
                animateScale(activityLayer, from: 0.9, to: 1.0, duration: 0.1, delay: 0.1, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false, animated: animated)

                let beginPosition = CGPoint(x: clTitleBeginPosition.x, y: activityLayer.position.y)
                let finalPosition = activityLayer.position
                animateSpring(activityLayer, from: NSValue(cgPoint: beginPosition), to: NSValue(cgPoint: finalPosition), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, animated: animated)
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
                    animateAlpha(sublayer, from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, animated: animated)
                }
            }
            find(for: .chatListOnlineNode, in: chatListItemSnapshot.layer).flatMap { onlineLayer in
                onlineLayer.rasterizationScale = UIScreenScale

                animateAlpha(onlineLayer, from: 1.0, to: 0.0, duration: 0.1, removeOnCompletion: false, animated: animated)
                animateScale(onlineLayer, from: 1.0, to: 0.3, duration: 0.1, removeOnCompletion: false, animated: animated)
            }
        }
    }

    // MARK: - Interface

    func updateState(_ state: State, sourceNode: ASDisplayNode, controller: ViewController, size: CGSize, scale: CGFloat, animated: Bool) {
        guard self.state != state else { return }
        self.state = state

        chatListItemSnapshot?.removeFromSuperview()
        chatTitleViewSnapshot?.removeFromSuperview()
        chatListItemSeparatorLayer?.removeFromSuperlayer()
        find(for: .localAvatarSnapshot, in: view.layer)?.removeFromSuperlayer()

        chatListItemSnapshot = sourceNode.view.snapshotContentTree()
        chatListItemSeparatorLayer = find(for: "separatorNode", in: sourceNode.supernode?.layer ?? sourceNode.layer)?.snapshotContentTree()
        _ = controller.navigationBar?.titleView?.snapshotView(afterScreenUpdates: true) // wait until renders
        chatTitleViewSnapshot = (controller.navigationBar?.titleView as? ChatTitleView)?.snapshotContentTree()

        chatListItemSnapshot.flatMap { view.addSubview($0) }
        chatTitleViewSnapshot.flatMap { view.addSubview($0) }
        chatListItemSeparatorLayer.flatMap { view.layer.addSublayer($0) }

        updateLayout(size: size, scale: scale, safeInsets: safeInsets, animated: animated)
    }

    // MARK: - Private. Help

    private func animateAlpha(_ layer: CALayer, from: CGFloat, to: CGFloat, duration: Double, delay: Double = 0.0, timingFunction: String = CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: Bool = true, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        if animated {
            layer.animateAlpha(from: from, to: to, duration: duration, delay: delay, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
        } else {
            layer.animateAlpha(from: from, to: to, duration: 0.0, delay: 0.0, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
        }
    }

    private func animateScale(_ layer: CALayer, from: CGFloat, to: CGFloat, duration: Double, delay: Double = 0.0, timingFunction: String = CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: Bool = true, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        if animated {
            layer.animateScale(from: from, to: to, duration: duration, delay: delay, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
        } else {
            layer.animateScale(from: from, to: to, duration: 0.0, delay: 0.0, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
        }
    }

    private func animateSpring(_ layer: CALayer, from: AnyObject, to: AnyObject, keyPath: String, duration: Double, delay: Double = 0.0, initialVelocity: CGFloat = 0.0, damping: CGFloat = 88.0, removeOnCompletion: Bool = true, additive: Bool = false, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        if animated {
            layer.animateSpring(from: from, to: to, keyPath: keyPath, duration: duration, delay: delay, initialVelocity: initialVelocity, damping: damping, removeOnCompletion: removeOnCompletion, additive: additive, completion: completion)
        } else {
            layer.animateSpring(from: from, to: to, keyPath: keyPath, duration: 0.0, delay: 0.0, initialVelocity: initialVelocity, damping: damping, removeOnCompletion: removeOnCompletion, additive: additive, completion: completion)
        }
    }

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
