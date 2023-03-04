import AsyncDisplayKit
import Display
import Foundation
import SwiftSignalKit
import UIKit

final class CallControllerKeyPreviewNode: ASDisplayNode {
    enum EffectStyle {
        case light
        case dark
    }

    private var effectStyle: EffectStyle = .light

    private let containerNode: ASDisplayNode
    private let contentBackgroundView: UIVisualEffectView
    private let emojiContainerNode: CallControllerKeyButton
    private let titleNode: ASTextNode
    private let subtitleNode: ASTextNode
    private let separatorNode: ASDisplayNode
    private let completeNode: ASTextNode

    private let dismiss: () -> Void

    init(keyText: String, effectStyle: EffectStyle, infoText: String, dismiss: @escaping () -> Void) {
        self.effectStyle = effectStyle

        containerNode = ASDisplayNode()

        contentBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: effectStyle == .light ? .light : .dark))

        emojiContainerNode = CallControllerKeyButton()
        emojiContainerNode.key = keyText
        emojiContainerNode.layer.anchorPoint = CGPoint(x: 1.0, y: 0.0)
        emojiContainerNode.isUserInteractionEnabled = false

        titleNode = ASTextNode()
        titleNode.displaysAsynchronously = false

        subtitleNode = ASTextNode()
        subtitleNode.displaysAsynchronously = false

        separatorNode = ASDisplayNode()
        separatorNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        completeNode = ASTextNode()
        completeNode.displaysAsynchronously = false
        completeNode.isUserInteractionEnabled = false

        self.dismiss = dismiss

        super.init()

        containerNode.layer.anchorPoint = CGPoint(x: 1.0, y: 0.0)
        containerNode.layer.masksToBounds = true
        containerNode.layer.cornerRadius = 20.0
        applySmoothRoundedCorners(containerNode.layer)

        titleNode.attributedText = NSAttributedString(string: "This call is end-to end encrypted", font: Font.semibold(16.0), textColor: .white, paragraphAlignment: .center)

        subtitleNode.attributedText = NSAttributedString(string: infoText, font: Font.regular(16.0), textColor: UIColor.white, paragraphAlignment: .center)

        completeNode.attributedText = NSAttributedString(string: "OK", font: Font.regular(20.0), textColor: .white, paragraphAlignment: .center)

        addSubnode(containerNode)
        addSubnode(emojiContainerNode)

        containerNode.view.addSubview(contentBackgroundView)
        containerNode.addSubnode(titleNode)
        containerNode.addSubnode(subtitleNode)

        containerNode.addSubnode(separatorNode)
        containerNode.addSubnode(completeNode)
    }

    override func didLoad() {
        super.didLoad()

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }

    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        let emojiSize = CGSize(width: 224.0, height: 68.0)
        let emojiFrame = CGRect(origin: CGPoint(x: (size.width - emojiSize.width) / 2.0, y: 10.0), size: emojiSize)
        transition.updatePosition(layer: emojiContainerNode.layer, position: CGPoint(x: emojiFrame.maxX, y: emojiFrame.minY))
        transition.updateBounds(layer: emojiContainerNode.layer, bounds: CGRect(origin: .zero, size: emojiSize))
        emojiContainerNode.updateLayout()

        let titleSize = titleNode.measure(CGSize(width: size.width - 16.0 * 2.0, height: .greatestFiniteMagnitude))
        let titleFrame = CGRect(x: 16.0, y: emojiFrame.maxY + 10.0, width: size.width - 16.0 * 2.0, height: titleSize.height)
        transition.updateFrame(node: titleNode, frame: titleFrame)

        let subtitleSize = subtitleNode.measure(CGSize(width: size.width - 16.0 * 2.0, height: .greatestFiniteMagnitude))
        let subtitleFrame = CGRect(x: 16.0, y: titleFrame.maxY + 10.0, width: size.width - 16.0 * 2.0, height: subtitleSize.height)
        transition.updateFrame(node: subtitleNode, frame: subtitleFrame)

        let separatorSize = CGSize(width: size.width, height: UIScreenPixel)
        let separatorFrame = CGRect(origin: CGPoint(x: 0.0, y: subtitleFrame.maxY + 20.0), size: separatorSize)
        transition.updateFrame(node: separatorNode, frame: separatorFrame)

        let completeSize = completeNode.measure(CGSize(width: size.width - 16.0 * 2.0, height: .greatestFiniteMagnitude))
        let completeFrame = CGRect(x: 16.0, y: separatorFrame.maxY + (56.0 - completeSize.height) / 2.0, width: size.width - 16.0 * 2.0, height: completeSize.height)
        transition.updateFrame(node: completeNode, frame: completeFrame)

        let contentBackgroundFrame = CGRect(x: 0.0, y: 0.0, width: size.width, height: separatorFrame.maxY + 56.0)
        transition.updateFrame(view: contentBackgroundView, frame: contentBackgroundFrame)

        let containerSize = CGSize(width: size.width, height: separatorFrame.maxY + 56.0)
        transition.updateFrame(node: containerNode, frame: CGRect(origin: .zero, size: containerSize))

        return containerSize
    }

    func animateIn(from rect: CGRect, fromNode: ASDisplayNode) {
        let converted = view.superview?.convert(rect, to: view) ?? rect

        let emojiFrom = CGPoint(x: converted.maxX, y: converted.minY)
        let emojiTo = emojiContainerNode.layer.position
        let emojiControlPoint = CGPoint(x: emojiTo.x + (emojiFrom.x - emojiTo.x) * 0.7, y: emojiTo.y + (emojiFrom.y - emojiTo.y) * 0.1)

        let emojiPath = CGMutablePath()
        emojiPath.move(to: emojiFrom)
        emojiPath.addCurve(to: emojiTo, control1: emojiControlPoint, control2: emojiControlPoint)

        let emojiAnimation = CAKeyframeAnimation(keyPath: "position")
        emojiAnimation.calculationMode = .paced
        emojiAnimation.fillMode = .both
        emojiAnimation.path = emojiPath
        emojiAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        emojiAnimation.duration = 0.3

        emojiContainerNode.layer.add(emojiAnimation, forKey: "position")
        emojiContainerNode.scale(value: true, transition: .animated(duration: 0.3, curve: .easeInOut))

        containerNode.layer.animateScale(from: 0.1, to: 1.0, duration: 0.3, delay: 0.1, timingFunction: kCAMediaTimingFunctionSpring)
        containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3, delay: 0.1, timingFunction: kCAMediaTimingFunctionSpring)
    }

    func animateOut(to rect: CGRect, toNode: ASDisplayNode, completion: @escaping () -> Void) {
        let converted = view.superview?.convert(rect, to: view) ?? rect

        let emojiFrom = emojiContainerNode.layer.position
        let emojiTo = CGPoint(x: converted.maxX, y: converted.minY)
        let emojiControlPoint = CGPoint(x: emojiFrom.x + (emojiTo.x - emojiFrom.x) * 0.7, y: emojiFrom.y + (emojiTo.y - emojiFrom.y) * 0.1)

        let emojiPath = CGMutablePath()
        emojiPath.move(to: emojiFrom)
        emojiPath.addCurve(to: emojiTo, control1: emojiControlPoint, control2: emojiControlPoint)

        let emojiAnimation = CAKeyframeAnimation(keyPath: "position")
        emojiAnimation.calculationMode = .paced
        emojiAnimation.fillMode = .both
        emojiAnimation.path = emojiPath
        emojiAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        emojiAnimation.duration = 0.3
        emojiAnimation.isRemovedOnCompletion = false

        emojiContainerNode.layer.add(emojiAnimation, forKey: "position")
        emojiContainerNode.scale(value: false, transition: .animated(duration: 0.3, curve: .easeInOut))

        containerNode.layer.animateScale(from: 1.0, to: 0.1, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false)
        containerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false) { _ in
            completion()
        }
    }

    func animateBlur(_ style: EffectStyle, transition: ContainedViewLayoutTransition) {
        guard self.effectStyle != style else { return }

        self.effectStyle = style
        transition.animateView { [weak self] in
            guard let self = self else { return }

            switch style {
            case .light:
                self.contentBackgroundView.effect = UIBlurEffect(style: .light)
            case .dark:
                self.contentBackgroundView.effect = UIBlurEffect(style: .dark)
            }
        }
    }

    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.dismiss()
        }
    }
}
