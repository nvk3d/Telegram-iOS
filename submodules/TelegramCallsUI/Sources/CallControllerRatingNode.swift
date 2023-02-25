import AsyncDisplayKit
import Display
import ManagedAnimationNode

private final class StarsContainerNode: ASDisplayNode {
    // MARK: - Properties

    var starsSelected: ((Int) -> Void)?

    private var didSelectStar: Bool = false
    private let animationSize: CGSize

    // MARK: - Gestures

    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapGestureAction(_:)))

    // MARK: - Nodes

    private let starNodes: [ASImageNode]
    private let animationNode: SimpleAnimationNode

    // MARK: - Init

    override init() {
        var stars: [ASImageNode] = []
        for _ in 0 ..< 5 {
            stars.append(ASImageNode())
        }
        starNodes = stars

        animationSize = CGSize(width: 126.0, height: 126.0)

        animationNode = SimpleAnimationNode(animationName: "anim_call_rating", size: animationSize, playOnce: true)
        animationNode.isUserInteractionEnabled = false
        animationNode.alpha = 0.0

        super.init()

        let emptyStarImage = generateTintedImage(image: UIImage(bundleImageName: "Call/CallStar"), color: .white)
        for starNode in starNodes {
            starNode.image = emptyStarImage
            addSubnode(starNode)
        }

        addSubnode(animationNode)

        view.addGestureRecognizer(tapGesture)
    }

    // MARK: - Life cycle

    override func measure(_ constrainedSize: CGSize) -> CGSize {
        let starSize: CGFloat = 42.0
        let interitemInset: CGFloat = 4.0
        let width: CGFloat = starSize * CGFloat(starNodes.count) + interitemInset * CGFloat(starNodes.count - 1)
        return CGSize(width: width, height: starSize)
    }

    func containerLayoutUpdated(_ size: CGSize, transition: ContainedViewLayoutTransition) {
        let starSize: CGFloat = 42.0
        let interitemInset: CGFloat = 4.0

        var offset: CGFloat = 0.0
        for starNode in starNodes {
            let frame = CGRect(x: offset, y: 0.0, width: starSize, height: starSize)
            transition.updateFrameAsPositionAndBounds(node: starNode, frame: frame)

            offset += starSize + interitemInset
        }
    }

    // MARK: - Private. Actions

    @objc
    private func tapGestureAction(_ sender: UITapGestureRecognizer) {
        guard !didSelectStar else { return }

        let location = sender.location(in: view)
        guard let starNodeIndex = starNodes.firstIndex(where: { $0.point(inside: convert(location, to: $0), with: nil) }) else { return }

        didSelectStar = true
        starsSelected?(starNodeIndex + 1)

        let filledImage = generateTintedImage(image: UIImage(bundleImageName: "Call/CallStarFilled"), color: .white)
        for i in 0 ..< starNodes.count {
            guard i <= starNodeIndex else { break }

            starNodes[i].image = filledImage

            let animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.values = [1.15, 1.0]
            animation.duration = 0.3
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            starNodes[i].layer.add(animation, forKey: "transform.scale")
        }

        if starNodeIndex >= starNodes.count - 2 {
            let selected = starNodes[starNodeIndex]
            animationNode.alpha = 1.0
            animationNode.frame = CGRect(
                origin: CGPoint(x: selected.position.x - animationSize.width / 2.0, y: selected.position.y - animationSize.height / 2.0),
                size: animationSize
            )
            animationNode.play()
        }
    }
}

private let titleFont = Font.semibold(16.0)
private let subtitleFont = Font.regular(16.0)

final class CallControllerRatingNode: ASDisplayNode {
    // MARK: - Properties

    var rateTapped: ((Int) -> Void)?

    private var rateSelected: Bool = false

    // MARK: - Nodes

    private let titleNode: TextNode
    private let subtitleNode: TextNode
    private let starsContainerNode: StarsContainerNode

    // MARK: - Init

    override init() {
        titleNode = TextNode()
        subtitleNode = TextNode()
        starsContainerNode = StarsContainerNode()

        super.init()

        backgroundColor = .white.withAlphaComponent(0.25)
        layer.cornerRadius = 20.0
        applySmoothRoundedCorners(layer)

        addSubnode(titleNode)
        addSubnode(subtitleNode)
        addSubnode(starsContainerNode)

        starsContainerNode.starsSelected = { [weak self] stars in
            self?.rateTapped?(stars)
        }
    }

    // MARK: - Life cycle

    func updateLayout(_ availableWidth: CGFloat) -> CGFloat {
        let widthForText: CGFloat = availableWidth - 32.0
        let (titleLayout, titleApply) = TextNode.asyncLayout(titleNode)(TextNodeLayoutArguments(
            attributedString: NSAttributedString(string: "Rate This Call", font: titleFont, textColor: .white),
            maximumNumberOfLines: 1,
            truncationType: .end,
            constrainedSize: CGSize(width: widthForText, height: .greatestFiniteMagnitude),
            alignment: .center
        ))
        let (subtitleLayout, subtitleApply) = TextNode.asyncLayout(subtitleNode)(TextNodeLayoutArguments(
            attributedString: NSAttributedString(string: "Please rate the quality of this call.", font: subtitleFont, textColor: .white),
            maximumNumberOfLines: 2,
            truncationType: .end,
            constrainedSize: CGSize(width: widthForText, height: .greatestFiniteMagnitude),
            alignment: .center
        ))

        let _ = titleApply()
        let _ = subtitleApply()

        let immediate: ContainedViewLayoutTransition = .immediate

        let titleFrame = CGRect(
            origin: CGPoint(x: (availableWidth - titleLayout.size.width) / 2.0, y: 20.0),
            size: titleLayout.size
        )
        immediate.updateFrameAsPositionAndBounds(node: titleNode, frame: titleFrame)

        let subtitleFrame = CGRect(
            origin: CGPoint(x: (availableWidth - subtitleLayout.size.width) / 2.0, y: titleFrame.maxY + 10.0),
            size: subtitleLayout.size
        )
        immediate.updateFrameAsPositionAndBounds(node: subtitleNode, frame: subtitleFrame)

        let starsContainerSize = starsContainerNode.measure(CGSize(width: availableWidth, height: 42.0))
        let starsContainerFrame = CGRect(
            origin: CGPoint(x: (availableWidth - starsContainerSize.width) / 2.0, y: subtitleFrame.maxY + 10.0),
            size: starsContainerSize
        )
        immediate.updateFrameAsPositionAndBounds(node: starsContainerNode, frame: starsContainerFrame)
        starsContainerNode.containerLayoutUpdated(starsContainerSize, transition: immediate)

        return starsContainerFrame.maxY + 20.0
    }
}
