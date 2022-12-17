import Display
import UIKit

final class StreamChatBlurredView: UIVisualEffectView {

    /// Returns the instance of UIBlurEffect.
    private let blurEffect = (NSClassFromString(["Effect", "Blur", "Custom", "_UI"].reversed().joined()) as! UIBlurEffect.Type).init()

    /**
     Tint color.

     The default value is nil.
     */
    var colorTint: UIColor? {
        get {
            if #available(iOS 14, *) {
                return ios14_colorTint
            } else {
                return _value(forKey: .colorTint)
            }
        }
        set {
            if #available(iOS 14, *) {
                ios14_colorTint = newValue
            } else {
                _setValue(newValue, forKey: .colorTint)
            }
        }
    }

    /**
     Tint color alpha.
     Don't use it unless `colorTint` is not nil.
     The default value is 0.0.
     */
    var colorTintAlpha: CGFloat {
        get { return _value(forKey: .colorTintAlpha) ?? 0.0 }
        set {
            if #available(iOS 14, *) {
                ios14_colorTint = ios14_colorTint?.withAlphaComponent(newValue)
            } else {
                _setValue(newValue, forKey: .colorTintAlpha)
            }
        }
    }

    /**
     Blur radius.

     The default value is 0.0.
     */
    var blurRadius: CGFloat {
        get {
            if #available(iOS 14, *) {
                return ios14_blurRadius
            } else {
                return _value(forKey: .blurRadius) ?? 0.0
            }
        }
        set {
            if #available(iOS 14, *) {
                ios14_blurRadius = newValue
            } else {
                _setValue(newValue, forKey: .blurRadius)
            }
        }
    }

    var saturationDeltaFactor: Double {
        get {
            if #available(iOS 14.0, *) {
                return ios14_saturationDeltaFactor
            } else {
                return _value(forKey: .saturationDeltaFactor) ?? 0.0
            }
        }
        set {
            if #available(iOS 14.0, *) {
                ios14_saturationDeltaFactor = newValue
            } else {
                _setValue(newValue, forKey: .saturationDeltaFactor)
            }
        }
    }

    /**
     Scale factor.

     The scale factor determines how content in the view is mapped from the logical coordinate space (measured in points) to the device coordinate space (measured in pixels).

     The default value is 1.0.
     */
    var scale: CGFloat {
        get { return _value(forKey: .scale) ?? 1.0 }
        set { _setValue(newValue, forKey: .scale) }
    }

    private var displayLinkAnimator: DisplayLinkAnimator?

    // MARK: - Initialization

    override init(effect: UIVisualEffect?) {
        super.init(effect: effect)

        scale = 1
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        scale = 1
    }

    // MARK: - Interface

    func updateBlurRadius(_ radius: CGFloat, transition: ContainedViewLayoutTransition) {
        displayLinkAnimator?.invalidate()

        if case let .animated(duration, _) = transition {
            let oldRadius: CGFloat = blurRadius
            let delta = radius - blurRadius

            displayLinkAnimator = DisplayLinkAnimator(duration: duration, from: 0.0, to: 1.0, update: { [weak self] progress in
                guard let self = self else { return }
                self.blurRadius = max(0.0, oldRadius + delta * progress)
            }, completion: { [weak self] in
                self?.displayLinkAnimator?.invalidate()
                self?.displayLinkAnimator = nil
            })
        } else {
            blurRadius = radius
        }
    }
}

// MARK: - Helpers
private extension StreamChatBlurredView {

    /// Returns the value for the key on the blurEffect.
    func _value<T>(forKey key: Key) -> T? {
        return blurEffect.value(forKeyPath: key.rawValue) as? T
    }

    /// Sets the value for the key on the blurEffect.
    func _setValue<T>(_ value: T?, forKey key: Key) {
        blurEffect.setValue(value, forKeyPath: key.rawValue)
        if #available(iOS 14, *) {} else {
            self.effect = blurEffect
        }
    }

    enum Key: String {
        // MARK: - Cases

        case colorTint
        case colorTintAlpha
        case blurRadius
        case scale
        case saturationDeltaFactor
    }

}

@available(iOS 14, *)
private extension UIVisualEffectView {
    var ios14_blurRadius: CGFloat {
        get {
            return gaussianBlur?.requestedValues?["inputRadius"] as? CGFloat ?? 0
        }
        set {
            prepareForChanges()
            gaussianBlur?.requestedValues?["inputRadius"] = newValue
            applyChanges()
        }
    }
    var ios14_colorTint: UIColor? {
        get {
            return sourceOver?.value(forKeyPath: "color") as? UIColor
        }
        set {
            prepareForChanges()
            sourceOver?.setValue(newValue, forKeyPath: "color")
            sourceOver?.perform(Selector((["apply", "Requested", "Effect", "To", "View:"].joined())), with: overlayView)
            applyChanges()
            overlayView?.backgroundColor = newValue
        }
    }
    var ios14_saturationDeltaFactor: Double {
        get {
            return backdropView?.requestedValues?["inputAmount"] as? Double ?? 0
        }
        set {
            prepareForChanges()
            _saturationDeltaFactor?.requestedValues?["inputAmount"] = newValue
            applyChanges()
        }
    }
}

private extension UIVisualEffectView {
    var backdropView: UIView? {
        return subview(of: NSClassFromString(["View", "Backdrop", "Effect", "Visual", "_UI"].reversed().joined()))
    }
    var overlayView: UIView? {
        return subview(of: NSClassFromString(["Subview", "Effect", "Visual", "_UI"].reversed().joined()))
    }
    var gaussianBlur: NSObject? {
        return backdropView?.value(forKey: "filters", withFilterType: "gaussianBlur")
    }
    var _saturationDeltaFactor: NSObject? {
        return backdropView?.value(forKey: "filters", withFilterType: "colorSaturate")
    }
    var sourceOver: NSObject? {
        return overlayView?.value(forKey: "viewEffects", withFilterType: "sourceOver")
    }
    func prepareForChanges() {
        self.effect = UIBlurEffect(style: .light)
        gaussianBlur?.setValue(1.0, forKeyPath: ["requested", "Scale", "Hint"].joined())
    }
    func applyChanges() {
        backdropView?.perform(Selector((["apply", "Requested", "Filter", "Effects"].joined())))
    }
}

private extension NSObject {
    var requestedValues: [String: Any]? {
        get { return value(forKeyPath: "requestedValues") as? [String: Any] }
        set { setValue(newValue, forKeyPath: "requestedValues") }
    }
    func value(forKey key: String, withFilterType filterType: String) -> NSObject? {
        let values = (value(forKeyPath: key) as? [NSObject]) ?? []
        return values.first { $0.value(forKeyPath: "filterType") as? String == filterType }
    }
}

private extension UIView {
    func subview(of classType: AnyClass?) -> UIView? {
        return subviews.first { type(of: $0) == classType }
    }
}
