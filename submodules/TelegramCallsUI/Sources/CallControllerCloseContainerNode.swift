import AsyncDisplayKit
import Display

private let maskSideInset: CGFloat = 20.0

private let defaultCornerRadius: CGFloat = 14.0
private let smallCornerRadius: CGFloat = 4.0

private let defaultButtonHeight: CGFloat = 50.0
private let largeButtonHeight: CGFloat = 60.0

private final class CloseTopButtonNode: ASButtonNode {
    // MARK: - Properties

    private(set) var isAnimatedIn: Bool = false
    private(set) var isAnimatedOut: Bool = false

    private var _title: NSAttributedString?

    // MARK: - Layers

    private let maskLayer: CAShapeLayer

    private let backgroundLayer: CALayer
    private let backgroundMaskLayer: CAShapeLayer

    // MARK: - Init

    override init() {
        maskLayer = CAShapeLayer()

        backgroundLayer = CALayer()
        backgroundLayer.contentsScale = UIScreen.main.scale
        
        backgroundMaskLayer = CAShapeLayer()
        backgroundMaskLayer.contentsScale = UIScreen.main.scale
        backgroundMaskLayer.fillRule = .evenOdd

        super.init()

        layer.cornerRadius = defaultCornerRadius
        layer.mask = maskLayer

        backgroundLayer.mask = backgroundMaskLayer
        layer.addSublayer(backgroundLayer)
    }

    // MARK: - Interface

    override func setTitle(_ title: String, with font: UIFont, with color: UIColor, for state: UIControl.State) {
        _title = NSAttributedString(string: title, font: font, textColor: color)
        updateTextMask(.immediate)
    }

    func animateIn(_ position: CGPoint, transition: ContainedViewLayoutTransition, completion: (() -> Void)? = nil) {
        guard !isAnimatedIn else { return }
        isAnimatedIn = true

        let beginPath = UIBezierPath(roundedRect: calculateMaskFrame(for: !isAnimatedIn, position: position, size: frame.size), cornerRadius: frame.size.height / 2.0).cgPath
        maskLayer.path = beginPath

        let endPath = UIBezierPath(roundedRect: calculateMaskFrame(for: isAnimatedIn, position: position, size: frame.size), cornerRadius: defaultCornerRadius).cgPath

        transition.updatePath(layer: maskLayer, path: endPath) { _ in
            completion?()
        }
    }

    func animateOut(_ transition: ContainedViewLayoutTransition, completion: (() -> Void)? = nil) {
        guard !isAnimatedOut else { completion?(); return }
        guard let path = maskLayer.path else { completion?(); return }
        isAnimatedOut = true

        let endPath = UIBezierPath(roundedRect: calculateMaskFrame(for: isAnimatedIn, position: .zero, size: frame.size), cornerRadius: smallCornerRadius).cgPath

        if case let .animated(duration, curve) = transition {
            let pathAnim = maskLayer.makeAnimation(
                from: path,
                to: endPath,
                keyPath: "path",
                timingFunction: curve.timingFunction,
                duration: duration / 5.0
            )
            maskLayer.add(pathAnim, forKey: "path")
        }

        maskLayer.path = endPath
        transition.updatePosition(layer: maskLayer, position: CGPoint(x: frame.size.width + maskSideInset, y: 0.0)) { _ in
            completion?()
        }
    }

    func updateBackgroundColor(_ color: UIColor, transition: ContainedViewLayoutTransition) {
        transition.updateBackgroundColor(layer: backgroundLayer, color: color)
    }

    func updateFrame(_ frame: CGRect, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(node: self, frame: frame)
        transition.updateFrame(layer: backgroundLayer, frame: CGRect(origin: .zero, size: frame.size))
        transition.updateFrame(layer: backgroundMaskLayer, frame: CGRect(origin: .zero, size: frame.size))
        updateTextMask(transition)
    }

    // MARK: - Private. Help

    private func calculateCornerRadius(for isAnimatedIn: Bool, size: CGSize) -> CGFloat {
        isAnimatedIn ? defaultCornerRadius : size.height / 2.0
    }

    private func calculateMaskFrame(for isAnimatedIn: Bool, position: CGPoint, size: CGSize) -> CGRect {
        if isAnimatedIn {
            return CGRect(origin: .zero, size: CGSize(width: size.width + maskSideInset, height: size.height))
        } else {
            var size = size
            size.height = defaultButtonHeight // largeButtonHeight
            let y = (defaultButtonHeight - size.height) / 2.0
            return CGRect(origin: CGPoint(x: position.x - size.height / 2.0, y: y), size: CGSize(width: size.height, height: size.height))
        }
    }

    private func updateTextMask(_ transition: ContainedViewLayoutTransition) {
        guard let title = _title else { backgroundMaskLayer.path = nil; return }

        let mutablePath = CGMutablePath()

        let textSize = title.size()
        let paths = generatePaths(title, position: CGPoint(x: (frame.size.width - textSize.width) / 2.0, y: 31.0))
        paths.forEach { mutablePath.addPath($0) }

        mutablePath.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: defaultCornerRadius).cgPath)

        transition.updatePath(layer: backgroundMaskLayer, path: mutablePath)
    }

    private func generatePaths(_ attributedString: NSAttributedString, position: CGPoint) -> [CGPath] {
        let line = CTLineCreateWithAttributedString(attributedString)
        guard let glyphRuns = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }

        var characterPaths: [CGPath] = []

        for glyphRun in glyphRuns {
            guard let attributes = CTRunGetAttributes(glyphRun) as? [String: AnyObject] else { continue }
            let font = attributes[kCTFontAttributeName as String] as! CTFont

            for index in 0 ..< CTRunGetGlyphCount(glyphRun) {
                let glyphRange = CFRangeMake(index, 1)

                var glyph = CGGlyph()
                CTRunGetGlyphs(glyphRun, glyphRange, &glyph)

                var characterPosition = CGPoint()
                CTRunGetPositions(glyphRun, glyphRange, &characterPosition)
                characterPosition.x += position.x
                characterPosition.y += position.y

                if let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) {
                    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: characterPosition.x, ty: characterPosition.y)
                    if let charPath = glyphPath.copy(using: &transform) {
                        characterPaths.append(charPath)
                    }
                }
            }
        }

        return characterPaths
    }
}

private final class CloseBottomButtonNode: ASButtonNode {
    // MARK: - Properties

    private(set) var isAnimatedIn: Bool = false

    // MARK: - Layers

    private let maskLayer: CAShapeLayer

    // MARK: - Init

    override init() {
        maskLayer = CAShapeLayer()

        super.init()

        layer.cornerRadius = defaultCornerRadius
        maskLayer.path = UIBezierPath(roundedRect: .zero, cornerRadius: .zero).cgPath
        layer.mask = maskLayer
    }

    // MARK: - Interface

    func animateIn(_ transition: ContainedViewLayoutTransition, completion: (() -> Void)? = nil) {
        guard !isAnimatedIn else { return }
        isAnimatedIn = true

        maskLayer.path = generatePath(cornerRadius: defaultCornerRadius, size: frame.size).cgPath

        transition.updatePosition(layer: maskLayer, position: CGPoint(x: frame.size.width + maskSideInset, y: 0.0)) { _ in
            completion?()
        }
    }

    // MARK: - Private. Help

    private func generatePath(cornerRadius: CGFloat, size: CGSize) -> UIBezierPath {
        let maskWidth: CGFloat = size.width + maskSideInset * 2.0
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -maskWidth, y: 0.0))
        path.addLine(to: CGPoint(x: cornerRadius, y: 0.0))
        path.addArc(withCenter: CGPoint(x: cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: -.pi / 2.0, endAngle: -.pi, clockwise: false)
        path.addLine(to: CGPoint(x: 0.0, y: size.height - cornerRadius))
        path.addArc(withCenter: CGPoint(x: cornerRadius, y: size.height - cornerRadius), radius: cornerRadius, startAngle: .pi, endAngle: .pi / 2.0, clockwise: false)
        path.addLine(to: CGPoint(x: -maskWidth, y: size.height))
        path.addLine(to: CGPoint(x: -maskWidth, y: 0.0))
        return path
    }
}

final class CallControllerCloseContainerNode: ASDisplayNode {
    // MARK: - Properties

    var requestAnimationEnded: ((Bool) -> Void)?

    private var isAnimatedIn: Bool = false
    private var requestedAnimationEnd: Bool = false

    // MARK: - Nodes

    private let bottomButton: CloseBottomButtonNode
    private let topButton: CloseTopButtonNode

    // MARK: - Init

    override init() {
        bottomButton = CloseBottomButtonNode()
        bottomButton.setTitle("Close", with: Font.semibold(17.0), with: .white, for: .normal)
        bottomButton.backgroundColor = .white.withAlphaComponent(0.25)

        topButton = CloseTopButtonNode()
        topButton.setTitle("Close", with: Font.semibold(17.0), with: .black, for: .normal)
        topButton.updateBackgroundColor(UIColor(rgb: 0xd92326), transition: .immediate)
        topButton.isUserInteractionEnabled = false

        super.init()

        addSubnode(bottomButton)
        addSubnode(topButton)

        bottomButton.addTarget(self, action: #selector(bottomButtonAction(_:)), forControlEvents: .touchUpInside)
    }

    // MARK: - Life cycle

    func updateLayout(_ size: CGSize, transition: ContainedViewLayoutTransition) -> CGFloat {
        let buttonHeight: CGFloat = defaultButtonHeight
        let temporaryHeight: CGFloat = isAnimatedIn ? buttonHeight : defaultButtonHeight //largeButtonHeight

        let buttonFrame = CGRect(origin: CGPoint(x: 0.0, y: (buttonHeight - temporaryHeight) / 2.0), size: CGSize(width: size.width, height: temporaryHeight))
        transition.updateFrame(node: bottomButton, frame: buttonFrame)
        topButton.updateFrame(buttonFrame, transition: transition)

        return buttonHeight
    }

    // MARK: - Interface

    func animateIn(_ position: CGPoint) {
        guard !isAnimatedIn else { return }

        _ = updateLayout(frame.size, transition: .immediate)
        isAnimatedIn = true

        let converted = supernode?.convert(position, to: self) ?? position
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.5, curve: .spring)

        _ = updateLayout(frame.size, transition: transition)
        topButton.updateBackgroundColor(.white, transition: transition)
        topButton.animateIn(converted, transition: transition) { [weak self] in
            guard let self = self else { return }

            let transition: ContainedViewLayoutTransition = .animated(duration: 5.0, curve: .linear)

            self.bottomButton.animateIn(transition)
            self.topButton.animateOut(transition) { [weak self] in
                guard let self = self else { return }
                self.requestAnimationEnded?(false)
            }
        }
    }

    // MARK: - Private. Actions

    @objc
    private func bottomButtonAction(_ sender: CloseBottomButtonNode) {
        guard !requestedAnimationEnd else { return }
        requestedAnimationEnd = true

        for button in [bottomButton, topButton] {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.duration = 0.1
            animation.fromValue = transform
            animation.toValue = CATransform3DScale(transform, 0.97, 0.97, 1)
            animation.repeatCount = 1
            animation.autoreverses = true
            button.layer.add(animation, forKey: "transform.scale")
        }

        requestAnimationEnded?(true)
    }
}
