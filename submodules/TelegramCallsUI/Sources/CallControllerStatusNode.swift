import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit

private let compactNameFont = Font.regular(22.0)
private let regularNameFont = Font.regular(28.0)

private let compactStatusFont = Font.regular(16.0)
private let regularStatusFont = Font.regular(16.0)

enum CallControllerStatusValue: Equatable {
    case text(string: String, loading: Bool)
    case timer((String, Bool) -> String, Double)
    case timestamp(icon: UIImage?)

    var isTimestamp: Bool {
        if case .timestamp = self { return true }
        return false
    }
    
    static func == (lhs: CallControllerStatusValue, rhs: CallControllerStatusValue) -> Bool {
        if case let .text(lText, lLoading) = lhs, case let .text(rText, rLoading) = rhs {
            return lText == rText && lLoading == rLoading
        }
        if case let .timer(_, lReferenceTime) = lhs, case let .timer(_, rReferenceTime) = rhs {
            return lReferenceTime == rReferenceTime
        }
        if case let .timestamp(lIcon) = lhs, case let .timestamp(rIcon) = rhs {
            return lIcon == nil && rIcon == nil || lIcon != nil && rIcon != nil
        }
        return false
    }
}

private final class CallControllerLoadingNode: ASDisplayNode {
    // MARK: - Properties

    var isAnimating: Bool { dotLayers[0].animation(forKey: "transform.scale") != nil }

    // MARK: - Layers

    private let dotLayers: [CALayer]

    // MARK: - Init

    override init() {
        dotLayers = [CALayer(), CALayer(), CALayer()]
        super.init()

        isLayerBacked = true

        dotLayers.forEach {
            $0.backgroundColor = UIColor.white.withAlphaComponent(0.5).cgColor
            $0.cornerRadius = 1.5
            layer.addSublayer($0)
        }
    }

    // MARK: - Life cycle

    override func measure(_ constrainedSize: CGSize) -> CGSize {
        let dotSize: CGFloat = 3.0
        let dotInteritemInset: CGFloat = 2.0
        return CGSize(width: dotSize * CGFloat(dotLayers.count) + dotInteritemInset * CGFloat(dotLayers.count - 1), height: dotSize)
    }

    func updateLayout(_ size: CGSize) {
        let dotSize: CGFloat = 3.0
        let dotInteritemInset: CGFloat = 2.0
        var dotOffset: CGFloat = 0.0

        for dotLayer in dotLayers {
            dotLayer.frame = CGRect(x: dotOffset, y: 0.0, width: dotSize, height: dotSize)
            dotOffset += dotSize + dotInteritemInset
        }
    }

    // MARK: - Interface

    func startAnimating() {
        isHidden = false
        guard !isAnimating else { return }

        var delay: CGFloat = 0.0
        for dot in dotLayers {
            let scale = dot.makeAnimation(
                from: NSNumber(value: Float(0.5)),
                to: NSNumber(value: Float(1.0)),
                keyPath: "transform.scale",
                timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue,
                duration: 0.6,
                delay: delay
            )
            scale.autoreverses = true
            scale.repeatCount = .infinity
            dot.add(scale, forKey: "transform.scale")

            let background = dot.makeAnimation(
                from: UIColor.white.withAlphaComponent(0.5).cgColor,
                to: UIColor.white.cgColor,
                keyPath: "backgroundColor",
                timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue,
                duration: 0.6,
                delay: delay
            )
            background.autoreverses = true
            background.repeatCount = .infinity
            dot.add(background, forKey: "backgroundColor")

            delay += 0.2
        }
    }

    func stopAnimating() {
        isHidden = true
        guard isAnimating else { return }

        dotLayers.forEach {
            $0.removeAnimation(forKey: "transform.scale")
            $0.removeAnimation(forKey: "backgroundColor")
        }
    }
}

final class CallControllerStatusNode: ASDisplayNode {
    private let titleNode: TextNode
    private let statusContainerNode: ASDisplayNode
    private let statusNode: TextNode
    private let statusMeasureNode: TextNode
    private let receptionNode: CallControllerReceptionNode
    private let loadingNode: CallControllerLoadingNode
    private let logoNode: ASImageNode
    
    private let titleActivateAreaNode: AccessibilityAreaNode
    private let statusActivateAreaNode: AccessibilityAreaNode
    
    var title: String = "" {
        didSet {
            if !oldValue.isEmpty, self.title != oldValue {
                guard let snapshotView = self.titleNode.view.snapshotView(afterScreenUpdates: false) else { return }

                snapshotView.frame = self.titleNode.frame
                self.view.insertSubview(snapshotView, aboveSubview: self.titleNode.view)

                snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false) { [weak snapshotView] _ in
                    snapshotView?.removeFromSuperview()
                }

                titleNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            }
        }
    }

    var subtitle: String = ""

    var status: CallControllerStatusValue = .text(string: "", loading: false) {
        didSet {
            if self.status != oldValue {
                self.statusTimer?.invalidate()

                if !status.isTimestamp, let snapshotView = self.statusContainerNode.view.snapshotView(afterScreenUpdates: false) {
                    snapshotView.frame = self.statusContainerNode.frame
                    self.view.insertSubview(snapshotView, belowSubview: self.statusContainerNode.view)
                    
                    snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                        snapshotView?.removeFromSuperview()
                    })
                    snapshotView.layer.animateScale(from: 1.0, to: 0.3, duration: 0.3, removeOnCompletion: false)
                    snapshotView.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: -snapshotView.frame.height / 3.0), duration: 0.3, delay: 0.0, removeOnCompletion: false, additive: true)
                    
                    self.statusContainerNode.layer.animateScale(from: 0.3, to: 1.0, duration: 0.3)
                    self.statusContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
                    self.statusContainerNode.layer.animatePosition(from: CGPoint(x: 0.0, y: snapshotView.frame.height / 3.0), to: CGPoint(), duration: 0.3, delay: 0.0, additive: true)
                }
                                
                if case .timer = self.status {
                    self.statusTimer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
                        if let strongSelf = self, let validLayoutWidth = strongSelf.validLayoutWidth {
                            let _ = strongSelf.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                        }
                    }, queue: Queue.mainQueue())
                    self.statusTimer?.start()
                } else {
                    if case .timestamp = self.status, endTimestamp != nil {
                        endTimestamp = CFAbsoluteTimeGetCurrent()
                    }
                    if let validLayoutWidth = self.validLayoutWidth {
                        let _ = self.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                    }
                }

                if status.isTimestamp {
                    logoNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
                    logoNode.layer.animatePosition(from: CGPoint(x: logoNode.position.x, y: logoNode.position.y - 5.0), to: logoNode.position, duration: 0.3)
                }
            }
        }
    }
    var reception: Int32? {
        didSet {
            if self.reception != oldValue {
                if let reception = self.reception {
                    self.receptionNode.reception = reception
                    
                    if oldValue == nil {
                        let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .spring)
                        transition.updateAlpha(node: self.receptionNode, alpha: 1.0)
                    }
                } else if self.reception == nil, oldValue != nil {
                    let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .spring)
                    transition.updateAlpha(node: self.receptionNode, alpha: 0.0)
                }
                
                if (oldValue == nil) != (self.reception != nil) {
                    if let validLayoutWidth = self.validLayoutWidth {
                        let _ = self.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                    }
                }
            }
        }
    }
    
    private var statusTimer: SwiftSignalKit.Timer?
    private var beginTimestamp: Double = CFAbsoluteTimeGetCurrent()
    private var endTimestamp: Double?
    private var validLayoutWidth: CGFloat?
    
    override init() {
        self.titleNode = TextNode()
        self.statusContainerNode = ASDisplayNode()
        self.statusNode = TextNode()
        self.statusNode.displaysAsynchronously = false
        self.statusMeasureNode = TextNode()
       
        self.receptionNode = CallControllerReceptionNode()
        self.receptionNode.alpha = 0.0
        
        self.logoNode = ASImageNode()
        self.logoNode.isHidden = true

        self.loadingNode = CallControllerLoadingNode()
        self.loadingNode.isHidden = true
        
        self.titleActivateAreaNode = AccessibilityAreaNode()
        self.titleActivateAreaNode.accessibilityTraits = .staticText
        
        self.statusActivateAreaNode = AccessibilityAreaNode()
        self.statusActivateAreaNode.accessibilityTraits = [.staticText, .updatesFrequently]
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.statusContainerNode)
        self.statusContainerNode.addSubnode(self.statusNode)
        self.statusContainerNode.addSubnode(self.receptionNode)
        self.statusContainerNode.addSubnode(self.logoNode)
        self.statusContainerNode.addSubnode(self.loadingNode)
        
        self.addSubnode(self.titleActivateAreaNode)
        self.addSubnode(self.statusActivateAreaNode)
    }
    
    deinit {
        self.statusTimer?.invalidate()
    }
    
    func setVisible(_ visible: Bool, transition: ContainedViewLayoutTransition) {
        let alpha: CGFloat = visible ? 1.0 : 0.0
        transition.updateAlpha(node: self.titleNode, alpha: alpha)
        transition.updateAlpha(node: self.statusContainerNode, alpha: alpha)
    }
    
    func updateLayout(constrainedWidth: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayoutWidth = constrainedWidth
        
        let nameFont: UIFont
        let statusFont: UIFont
        if constrainedWidth < 330.0 {
            nameFont = compactNameFont
            statusFont = compactStatusFont
        } else {
            nameFont = regularNameFont
            statusFont = regularStatusFont
        }
        
        var statusOffset: CGFloat = 0.0
        let statusText: String
        let statusMeasureText: String
        var statusDisplayLogo: Bool = false
        var statusIcon: UIImage? = nil
        var statusLoading: Bool = false

        switch self.status {
        case let .text(text, loading):
            let text = text.replacingOccurrences(of: "...", with: "")
            statusText = text
            statusMeasureText = text
            if loading {
                statusLoading = true
                statusOffset -= 7.5
            }
        case let .timer(format, referenceTime):
            beginTimestamp = referenceTime
            let end = CFAbsoluteTimeGetCurrent()
            endTimestamp = end

            let duration = Int32(end - beginTimestamp)
            let formattedStrings = formattedTimestamp(duration)
            let durationString: String = formattedStrings.string
            let measureDurationString: String = formattedStrings.measureString

            let _statusText = format(durationString, false)
            let _statusMeasureText = format(measureDurationString, true)
            statusLoading = _statusText.hasSuffix("...")

            if statusLoading {
                statusText = _statusText.replacingOccurrences(of: "...", with: "")
                statusMeasureText = _statusMeasureText.replacingOccurrences(of: "...", with: "")
                statusOffset -= 7.5
            } else {
                statusText = _statusText
                statusMeasureText = _statusMeasureText
            }
            if self.reception != nil {
                statusOffset += 8.0
            }
        case let .timestamp(icon):
            let end = endTimestamp ?? beginTimestamp
            let duration = Int32(end - beginTimestamp)
            let formattedStrings = formattedTimestamp(duration)

            statusText = formattedStrings.string
            statusMeasureText = formattedStrings.measureString

            if icon != nil {
                statusDisplayLogo = true
                statusIcon = icon
                statusOffset += 8.0
            }
        }
        
        let spacing: CGFloat = 1.0
        let (titleLayout, titleApply) = TextNode.asyncLayout(self.titleNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: self.title, font: nameFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets(top: 2.0, left: 2.0, bottom: 2.0, right: 2.0)))
        let (statusMeasureLayout, statusMeasureApply) = TextNode.asyncLayout(self.statusMeasureNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: statusMeasureText, font: statusFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20.0, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets(top: 2.0, left: 2.0, bottom: 2.0, right: 2.0)))
        let (statusLayout, statusApply) = TextNode.asyncLayout(self.statusNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: statusText, font: statusFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20.0, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets(top: 2.0, left: 2.0, bottom: 2.0, right: 2.0)))
        
        let _ = titleApply()
        let _ = statusApply()
        let _ = statusMeasureApply()
        
        self.titleActivateAreaNode.accessibilityLabel = self.title
        self.statusActivateAreaNode.accessibilityLabel = statusText
        
        self.titleNode.frame = CGRect(origin: CGPoint(x: floor((constrainedWidth - titleLayout.size.width) / 2.0), y: 0.0), size: titleLayout.size)
        self.statusContainerNode.frame = CGRect(origin: CGPoint(x: 0.0, y: titleLayout.size.height + spacing), size: CGSize(width: constrainedWidth, height: statusLayout.size.height))
        self.statusNode.frame = CGRect(origin: CGPoint(x: floor((constrainedWidth - statusMeasureLayout.size.width) / 2.0) + statusOffset, y: 0.0), size: statusLayout.size)
        self.receptionNode.frame = CGRect(origin: CGPoint(x: self.statusNode.frame.minX - receptionNodeSize.width + 4.0, y: (statusContainerNode.frame.height - receptionNodeSize.height) / 2.0), size: receptionNodeSize)

        self.logoNode.image = statusIcon
        self.logoNode.isHidden = !statusDisplayLogo

        let defaultImageSize = CGSize(width: 28.0, height: 28.0)
        let imageSize = logoNode.image?.size ?? defaultImageSize

        if let firstLineRect = statusMeasureLayout.linesRects().first {
            let firstLineOffset = floor((statusMeasureLayout.size.width - firstLineRect.width) / 2.0)
            self.logoNode.frame = CGRect(origin: CGPoint(x: self.statusNode.frame.minX + firstLineOffset - imageSize.width, y: (self.statusContainerNode.frame.height - imageSize.height) / 2.0), size: imageSize)
        }

        let loadingSize = self.loadingNode.measure(CGSize(width: constrainedWidth, height: titleLayout.size.height))
        let loadingFrame = CGRect(origin: CGPoint(x: statusNode.frame.maxX + 6.0, y: (self.statusContainerNode.frame.height - loadingSize.height) / 2.0), size: loadingSize)
        self.loadingNode.frame = loadingFrame
        loadingNode.updateLayout(loadingSize)

        if statusLoading {
            loadingNode.startAnimating()
        } else {
            loadingNode.stopAnimating()
        }
        
        self.titleActivateAreaNode.frame = self.titleNode.frame
        self.statusActivateAreaNode.frame = self.statusContainerNode.frame
        
        return titleLayout.size.height + spacing + statusLayout.size.height
    }

    private func formattedTimestamp(_ duration: Int32) -> (string: String, measureString: String) {
        let durationString: String
        let measureDurationString: String

        if duration > 60 * 60 {
            durationString = String(format: "%02d:%02d:%02d", arguments: [duration / 3600, (duration / 60) % 60, duration % 60])
            measureDurationString = "00:00:00"
        } else {
            durationString = String(format: "%02d:%02d", arguments: [(duration / 60) % 60, duration % 60])
            measureDurationString = "00:00"
        }

        return (string: durationString, measureString: measureDurationString)
    }
}


private final class CallControllerReceptionNodeParameters: NSObject {
    let reception: Int32
    
    init(reception: Int32) {
        self.reception = reception
    }
}

private let receptionNodeSize = CGSize(width: 24.0, height: 10.0)

final class CallControllerReceptionNode : ASDisplayNode {
    var reception: Int32 = 4 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    override init() {
        super.init()
        
        self.isOpaque = false
        self.isLayerBacked = true
    }
    
    override func drawParameters(forAsyncLayer layer: _ASDisplayLayer) -> NSObjectProtocol? {
        return CallControllerReceptionNodeParameters(reception: self.reception)
    }
    
    @objc override class func draw(_ bounds: CGRect, withParameters parameters: Any?, isCancelled: () -> Bool, isRasterizing: Bool) {
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        
        if let parameters = parameters as? CallControllerReceptionNodeParameters{
            let width: CGFloat = 3.0
            var spacing: CGFloat = 1.5
            if UIScreenScale > 2 {
                spacing = 4.0 / 3.0
            }
            
            for i in 0 ..< 4 {
                let height = 4.0 + 2.0 * CGFloat(i)
                let rect = CGRect(x: bounds.minX + CGFloat(i) * (width + spacing), y: receptionNodeSize.height - height, width: width, height: height)
                
                if i >= parameters.reception {
                    context.setAlpha(0.4)
                }
                
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 0.5)
                context.addPath(path.cgPath)
                context.fillPath()
            }
        }
    }
}
