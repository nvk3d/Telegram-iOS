import AsyncDisplayKit
import Display
import Foundation
import SwiftSignalKit
import UIKit

private let emojiFont = Font.regular(28.0)
private let textFont = Font.regular(15.0)

private let labelFont = Font.regular(40.0)

private class EmojiContainerItemNode: ASDisplayNode {
    var emoji: String = "" {
        didSet {
            node.attributedText = NSAttributedString(string: emoji, font: labelFont, textColor: .black)
            updateLayout()
        }
    }

    private let containerNode: ASDisplayNode
    private let node: ImmediateTextNode

    override init() {
        self.containerNode = ASDisplayNode()
        self.node = ImmediateTextNode()

        super.init()

        self.addSubnode(self.containerNode)
        self.containerNode.addSubnode(self.node)
    }

    func updateLayout() {
        let containerSize = bounds.size
        containerNode.position = CGPoint(x: bounds.size.width / 2.0, y: bounds.size.height / 2.0)
        containerNode.bounds = CGRect(origin: .zero, size: containerSize)

        let nodeSize = node.updateLayout(CGSize(width: 100.0, height: 100.0))
        node.position = CGPoint(x: containerSize.width / 2.0, y: containerSize.height / 2.0)
        node.bounds = CGRect(origin: .zero, size: nodeSize)
    }
}

private final class EmojiContainerNode: ASDisplayNode {
    private let containerNode: ASDisplayNode
    private let nodes: [EmojiContainerItemNode]

    var key: String = "" {
        didSet {
            var index = 0
            for emoji in self.key {
                guard index < 4 else {
                    return
                }
                self.nodes[index].emoji = String(emoji)
                index += 1
            }
        }
    }

    override init() {
        self.containerNode = ASDisplayNode()
        self.nodes = (0 ..< 4).map { _ in EmojiContainerItemNode() }

        super.init()

        self.addSubnode(self.containerNode)
        self.nodes.forEach({ self.containerNode.addSubnode($0) })
    }

    override func measure(_ constrainedSize: CGSize) -> CGSize {
        CGSize(width: 230.0, height: 68.0)
    }

    func animateIn() {
        let minimizedContainerSize = CGSize(width: 122.0, height: 44.0)
        let minimizedNodeSize = CGSize(width: 24.0, height: 24.0)
        let minimizedInteritemInset: CGFloat = 2.0

        let expandedContainerSize = CGSize(width: 230.0, height: 68.0)
        let expandedNodeSize = CGSize(width: 48.0, height: 48.0)
        let expandedInteritemInset: CGFloat = 6.0

        var minimizedOffsetX: CGFloat = (expandedContainerSize.width - minimizedContainerSize.width) / 2.0 + 10.0
        var expandedOffsetX: CGFloat = 10.0

        for node in nodes {
            node.layer.animatePosition(
                from: CGPoint(x: minimizedOffsetX + minimizedNodeSize.width / 2.0, y: expandedContainerSize.height / 2.0),
                to: CGPoint(x: expandedOffsetX + expandedNodeSize.width / 2.0, y: expandedContainerSize.height / 2.0),
                duration: 0.3
            )
            node.layer.animateScale(
                from: minimizedNodeSize.width / expandedNodeSize.width,
                to: 1.0,
                duration: 0.3
            )

            minimizedOffsetX += minimizedNodeSize.width + minimizedInteritemInset
            expandedOffsetX += expandedNodeSize.width + expandedInteritemInset
        }
    }

    func updateLayout() {
        self.containerNode.frame = self.bounds

        let nodeSize = CGSize(width: 48.0, height: 48.0)
        let interitemInset: CGFloat = 6.0
        var offsetX: CGFloat = 10.0

        for node in self.nodes {
            node.frame = CGRect(origin: CGPoint(x: offsetX, y: 10.0), size: nodeSize)
            node.updateLayout()

            offsetX += nodeSize.width + interitemInset
        }
    }
}

final class CallControllerKeyPreviewNode: ASDisplayNode {
    private let contentBackgroundView: UIVisualEffectView
    private let emojiContainerNode: EmojiContainerNode
    private let titleNode: ASTextNode
    private let subtitleNode: ASTextNode

    private let completeBackgroundView: UIVisualEffectView
    private let completeNode: ASTextNode

    private let dismiss: () -> Void

    init(keyText: String, infoText: String, dismiss: @escaping () -> Void) {
        contentBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .light))

        emojiContainerNode = EmojiContainerNode()
        emojiContainerNode.key = keyText
        emojiContainerNode.displaysAsynchronously = false

        titleNode = ASTextNode()
        titleNode.displaysAsynchronously = false

        subtitleNode = ASTextNode()
        subtitleNode.displaysAsynchronously = false

        completeBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .light))

        completeNode = ASTextNode()
        completeNode.displaysAsynchronously = false
        completeNode.isUserInteractionEnabled = false

        self.dismiss = dismiss

        super.init()

        layer.masksToBounds = true
        layer.cornerRadius = 20.0
        applySmoothRoundedCorners(layer)

        titleNode.attributedText = NSAttributedString(string: "This call is end-to end encrypted", font: Font.semibold(16.0), textColor: .white, paragraphAlignment: .center)

        subtitleNode.attributedText = NSAttributedString(string: infoText, font: Font.regular(16.0), textColor: UIColor.white, paragraphAlignment: .center)

        completeNode.attributedText = NSAttributedString(string: "OK", font: Font.regular(20.0), textColor: .white, paragraphAlignment: .center)

        view.addSubview(contentBackgroundView)
        addSubnode(emojiContainerNode)
        addSubnode(titleNode)
        addSubnode(subtitleNode)

        view.addSubview(completeBackgroundView)
        addSubnode(completeNode)
    }

    override func didLoad() {
        super.didLoad()

        completeBackgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }

    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        let emojiSize = emojiContainerNode.measure(size)
        let emojiFrame = CGRect(origin: CGPoint(x: (size.width - emojiSize.width) / 2.0, y: (size.height - emojiSize.height) / 2.0), size: emojiSize)
        transition.updateFrameAsPositionAndBounds(node: emojiContainerNode, frame: emojiFrame)
        emojiContainerNode.updateLayout()

        let titleSize = titleNode.measure(CGSize(width: size.width - 28.0 * 2.0, height: .greatestFiniteMagnitude))
        let titleFrame = CGRect(x: 28.0, y: emojiFrame.maxY + 10.0, width: size.width - 28.0 * 2.0, height: titleSize.height)
        transition.updateFrame(node: titleNode, frame: titleFrame)

        let subtitleSize = subtitleNode.measure(CGSize(width: size.width - 16.0 * 2.0, height: .greatestFiniteMagnitude))
        let subtitleFrame = CGRect(x: 16.0, y: titleFrame.maxY + 10.0, width: subtitleSize.width, height: subtitleSize.height)
        transition.updateFrame(node: subtitleNode, frame: subtitleFrame)

        let contentBackgroundFrame = CGRect(x: 0.0, y: 0.0, width: size.width, height: subtitleFrame.maxY + 20.0)
        transition.updateFrame(view: contentBackgroundView, frame: contentBackgroundFrame)

        let completeBackgroundFrame = CGRect(x: 0.0, y: contentBackgroundFrame.maxY + UIScreenPixel, width: size.width, height: 57.0)
        transition.updateFrame(view: completeBackgroundView, frame: completeBackgroundFrame)

        let completeSize = completeNode.measure(CGSize(width: size.width - 16.0 * 2.0, height: .greatestFiniteMagnitude))
        let completeFrame = CGRect(x: 16.0, y: 16.0, width: size.width - 16.0, height: completeSize.height)
        transition.updateFrame(node: completeNode, frame: completeFrame)

        return CGSize(width: size.width, height: completeBackgroundFrame.maxY)
    }

    func animateIn(from rect: CGRect, fromNode: ASDisplayNode) {
        let rect = CGRect(x: rect.origin.x + 10.0, y: rect.origin.y + 10.0, width: rect.size.width - 20.0, height: rect.size.height - 20.0)

        emojiContainerNode.layer.animatePosition(from: CGPoint(x: rect.midX, y: rect.midY), to: emojiContainerNode.layer.position, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
        emojiContainerNode.animateIn()

        /*self.keyTextNode.layer.animatePosition(from: CGPoint(x: rect.midX, y: rect.midY), to: self.keyTextNode.layer.position, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
        if let transitionView = fromNode.view.snapshotView(afterScreenUpdates: false) {
            self.view.addSubview(transitionView)
            transitionView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            transitionView.layer.animatePosition(from: CGPoint(x: rect.midX, y: rect.midY), to: self.keyTextNode.layer.position, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { [weak transitionView] _ in
                transitionView?.removeFromSuperview()
            })
            transitionView.layer.animateScale(from: 1.0, to: self.keyTextNode.frame.size.width / rect.size.width, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        }
        self.keyTextNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)

        self.keyTextNode.layer.animateScale(from: rect.size.width / self.keyTextNode.frame.size.width, to: 1.0, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)*/

//        self.infoTextNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
//
//        UIView.animate(withDuration: 0.3, animations: {
//            if #available(iOS 9.0, *) {
//                self.effectView.effect = UIBlurEffect(style: .dark)
//            } else {
//                self.effectView.alpha = 1.0
//            }
//        })
    }

    func animateOut(to rect: CGRect, toNode: ASDisplayNode, completion: @escaping () -> Void) {
        let rect = CGRect(x: rect.origin.x + 10.0, y: rect.origin.y + 10.0, width: rect.size.width - 20.0, height: rect.size.height - 20.0)

        emojiContainerNode.layer.animatePosition(from: emojiContainerNode.layer.position, to: CGPoint(x: rect.midX, y: rect.midY), duration: 0.3)

        /*self.keyTextNode.layer.animatePosition(from: self.keyTextNode.layer.position, to: CGPoint(x: rect.midX + 2.0, y: rect.midY), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { _ in
            completion()
        })
        self.keyTextNode.layer.animateScale(from: 1.0, to: rect.size.width / (self.keyTextNode.frame.size.width - 2.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)*/

//        self.infoTextNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
//
//        UIView.animate(withDuration: 0.3, animations: {
//            if #available(iOS 9.0, *) {
//                self.effectView.effect = nil
//            } else {
//                self.effectView.alpha = 0.0
//            }
//        })
    }

    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.dismiss()
        }
    }
}
