import Foundation
import UIKit
import AsyncDisplayKit

private final class SwitchNodeViewLayer: CALayer {
    override func setNeedsDisplay() {
    }
}

private final class SwitchNodeView: UISwitch {
    // MARK: - Class. Properties

    override class var layerClass: AnyClass {
        if #available(iOS 26.0, *) {
            return super.layerClass
        } else {
            return SwitchNodeViewLayer.self
        }
    }

    // MARK: - Properties

    var actionImagePosition: CGPoint? {
        if let actionImageView {
            let actionPositionInRoot = actionImageView.layer.superlayer?.convert(actionImageView.layer.position, to: layer) ?? actionImageView.layer.position
            return CGPoint(x: actionPositionInRoot.x, y: bounds.height / 2.0)
        }
        return nil
    }

    var additionalContext: SwitchNodeAdditionalContext?

    private var interactionInProgress = false

    // MARK: - Views

    private weak var actionImageView: UIImageView?

    // MARK: - Init

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)

        if #available(iOS 26.0, *) {} else {
            if let pressGesture: UILongPressGestureRecognizer = findGesture(in: self) {
                pressGesture.addTarget(self, action: #selector(pressAction(_:)))
            }
            if let panGesture: UIPanGestureRecognizer = findGesture(in: self) {
                panGesture.addTarget(self, action: #selector(panAction(_:)))
            }
            var imageViews: [UIImageView] = []
            grabAllTypeViews(from: self, in: &imageViews)

            actionImageView = imageViews.last
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Life cycle

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        additionalContext?.didMove(to: superview)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateActionImage()
    }

    // MARK: - Interface

    func setActionImageHidden(_ hidden: Bool, transition: ContainedViewLayoutTransition) {
        if let actionImageView {
            transition.updateAlpha(layer: actionImageView.layer, alpha: hidden ? 0.0 : 1.0, beginWithCurrentState: actionImageView.layer.animation(forKey: "opacity") != nil)
        }
    }

    func updateActionImage() {
        if let actionImageView {
            additionalContext?.actionImageUpdated(actionImageView)
        }
    }

    // MARK: - Private. Actions

    @objc
    private func panAction(_ sender: UIPanGestureRecognizer) {
        updateInteractionProgress(sender.state)
        updateActionImage()
    }

    @objc
    private func pressAction(_ sender: UILongPressGestureRecognizer) {
        updateInteractionProgress(sender.state)
        updateActionImage()
    }

    // MARK: - Private. Update

    private func updateInteractionProgress(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            if !interactionInProgress {
                interactionInProgress = true
                additionalContext?.interactionBegan()
            }
        case .cancelled, .ended, .failed:
            if interactionInProgress {
                interactionInProgress = false
                additionalContext?.interactionEnded()
            }
        default:
            break
        }
    }

    // MARK: - Private. Help

    private func findGesture<T: UIGestureRecognizer>(in view: UIView) -> T? {
        if let founded = view.gestureRecognizers?.first(where: { $0 is T }) as? T {
            return founded
        }
        for subview in view.subviews {
            if let founded: T = findGesture(in: subview) {
                return founded
            }
        }
        return nil
    }

    private func grabAllTypeViews<T: UIView>(from view: UIView, in founded: inout [T]) {
        if let f = view as? T {
            founded.append(f)
        }
        for subview in view.subviews {
            grabAllTypeViews(from: subview, in: &founded)
        }
    }
}

public protocol SwitchNodeAdditionalContext: AnyObject {
    // MARK: - Interface

    func actionImageUpdated(_ actionView: UIView)

    func interactionBegan()
    func interactionEnded()

    func didMove(to superview: UIView?)
}

open class SwitchNode: ASDisplayNode {
    public static var maybeSetupWithAdditionalContext: ((SwitchNode) -> Void)?

    public var actionImagePosition: CGPoint? {
        (view as? SwitchNodeView)?.actionImagePosition
    }
    public var additionalContext: SwitchNodeAdditionalContext?

    public var valueUpdated: ((Bool) -> Void)?
    
    public var frameColor = UIColor(rgb: 0xe0e0e0) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.frameColor {
                    (self.view as! UISwitch).tintColor = self.frameColor
                }
            }
        }
    }
    public var handleColor = UIColor(rgb: 0xffffff) {
        didSet {
            if self.isNodeLoaded {
                //(self.view as! UISwitch).thumbTintColor = self.handleColor
            }
        }
    }
    public var contentColor = UIColor(rgb: 0x42d451) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.contentColor {
                    (self.view as! UISwitch).onTintColor = self.contentColor
                }
            }
        }
    }
    
    private var _isOn: Bool = false
    public var isOn: Bool {
        get {
            return self._isOn
        } set(value) {
            if (value != self._isOn) {
                self._isOn = value
                if self.isNodeLoaded {
                    (self.view as! UISwitch).setOn(value, animated: false)
                }
            }
        }
    }

    public override var frame: CGRect {
        get {
            super.frame
        } set(value) {
            super.frame = value
            (view as? SwitchNodeView)?.updateActionImage()
        }
    }

    override public init() {
        super.init()

        if #available(iOS 26.0, *) {} else {
            Self.maybeSetupWithAdditionalContext?(self)
        }

        self.setViewBlock({
            return SwitchNodeView()
        })
    }
    
    override open func didLoad() {
        super.didLoad()
        
        self.view.isAccessibilityElement = false
        
        (self.view as! UISwitch).backgroundColor = self.backgroundColor
        (self.view as! UISwitch).tintColor = self.frameColor
        (self.view as! UISwitch).onTintColor = self.contentColor
        
        (self.view as! UISwitch).setOn(self._isOn, animated: false)
        
        (self.view as! UISwitch).addTarget(self, action: #selector(switchValueChanged(_:)), for: .valueChanged)

        if let view = view as? SwitchNodeView {
            view.additionalContext = additionalContext
        }
    }

    public func setActionImageHidden(_ hidden: Bool, transition: ContainedViewLayoutTransition) {
        (view as? SwitchNodeView)?.setActionImageHidden(hidden, transition: transition)
    }

    public func setOn(_ value: Bool, animated: Bool) {
        self._isOn = value
        if self.isNodeLoaded {
            (self.view as! UISwitch).setOn(value, animated: animated)
        }
    }
    
    override open func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        if #available(iOS 26.0, *) {
            return CGSize(width: 63.0, height: 28.0)
        } else {
            return CGSize(width: 51.0, height: 31.0)
        }
    }
    
    @objc func switchValueChanged(_ view: UISwitch) {
        self._isOn = view.isOn
        self.valueUpdated?(view.isOn)
    }
}
