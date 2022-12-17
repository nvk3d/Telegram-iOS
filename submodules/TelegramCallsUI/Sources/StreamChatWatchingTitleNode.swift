import AsyncDisplayKit
import Display
import TelegramPresentationData

private extension Array {
    // MARK: - Interface

    func element(at index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

final class StreamChatWatchingTitleNode: ASDisplayNode {
    // MARK: - Children

    private enum TextAction: Equatable {
        // MARK: - Cases

        case add
        case update
        case remove(CGRect)
        case none
    }

    // MARK: - Properties

    private(set) var title: String = ""
    private let theme: PresentationTheme

    private var layout: ContainerViewLayout?

    // MARK: - Nodes

    private let containerNode = ASDisplayNode()
    private var textNodes: [ASTextNode] = []

    // MARK: - Init

    init(theme: PresentationTheme) {
        self.theme = theme

        super.init()

        addSubnode(containerNode)
    }

    // MARK: - Life cycle

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.layout = layout

        let reversedCharacters = Array(title.reversed())
        var index = 0
        var mappedNodes: [(node: ASTextNode, snapshot: UIView?, newText: String?, action: TextAction)] = []

        while index < reversedCharacters.count {
            let currentNode: ASTextNode
            let currentText = String(reversedCharacters[index])

            if let textNode = textNodes.element(at: textNodes.count - 1 - index) {
                currentNode = textNode
            } else {
                currentNode = makeTextNode()
                containerNode.addSubnode(currentNode)
                textNodes.insert(currentNode, at: 0)
            }

            let snapshot = currentNode.attributedText != nil ? currentNode.view.snapshotContentTree() : nil
            mappedNodes.insert((node: currentNode, snapshot: snapshot, newText: currentText, action: textAction(old: currentNode.attributedText, new: currentText)), at: 0)

            index += 1
        }

        while textNodes.count - 1 - index >= 0 {
            let textNode = textNodes.remove(at: textNodes.count - 1 - index)
            let rect = CGRect(origin: CGPoint(x: textNode.frame.minX, y: textNode.frame.minY), size: textNode.frame.size)
            mappedNodes.insert((node: textNode, snapshot: nil, newText: nil, action: .remove(rect)), at: 0)
        }

        // Gradient colors
//        UIColor(rgb: 0x0077ff),
//        UIColor(rgb: 0x6b93ff),
//        UIColor(rgb: 0x8878ff),
//        UIColor(rgb: 0xe46ace)

        let font: UIFont = Font.bold(48.0)
        let textColorStart = UIColor(rgb: 0x0077ff)
        let textColorEnd = UIColor(rgb: 0xe46ace)
        let textColorStep = 1.0 / CGFloat(textNodes.count + 1)

        var existedTextIndex: Int = 0
        var offsetX: CGFloat = 0.0

        for (index, mappedNode) in mappedNodes.enumerated() {
            let delay: Double = Double((mappedNodes.count - 1 - index)) * 0.05
            let textNode = mappedNode.node

            let _colorPercent = textColorStep * CGFloat(existedTextIndex)
            let _colorStart = color(start: textColorStart, end: textColorEnd, percent: _colorPercent)
            let _colorEnd = color(start: textColorStart, end: textColorEnd, percent: _colorPercent + textColorStep)
            let textColor = UIColor(patternImage: generateGradientImage(size: CGSize(width: 50.0, height: 50.0), colors: [_colorStart, _colorEnd], locations: [0.0, 1.0], direction: .diagonal)!)

            switch mappedNode.action {
            case .add:
                textNode.attributedText = NSAttributedString(string: mappedNode.newText ?? "", font: font, textColor: textColor)

                let size = textNode.measure(CGSize(width: 50.0, height: layout.size.height))
                let position = CGPoint(x: offsetX + size.width / 2.0, y: size.height / 2.0)

                textNode.alpha = 0.0
                textNode.position = CGPoint(x: position.x, y: position.y + size.height / 4.0)
                textNode.transform = CATransform3DMakeScale(0.0, 0.0, 1.0)

                transition.updateAlpha(node: textNode, alpha: 1.0, delay: delay)
                transition.updateTransformScale(node: textNode, scale: 1.0, delay: delay)
                transition.updateFrameAsPositionAndBounds(
                    node: textNode,
                    frame: CGRect(origin: CGPoint(x: position.x - size.width / 2.0, y: position.y - size.height / 2.0), size: size),
                    delay: delay
                )

                offsetX += size.width

            case .update:
                textNode.attributedText = NSAttributedString(string: mappedNode.newText ?? "", font: font, textColor: textColor)

                let size = textNode.measure(CGSize(width: 50.0, height: layout.size.height))
                let position = CGPoint(x: offsetX + size.width / 2.0, y: size.height / 2.0)

                let oldPosition = textNode.position

                if let snapshot = mappedNode.snapshot {
                    snapshot.frame = textNode.frame
                    containerNode.view.insertSubview(snapshot, belowSubview: textNode.view)

                    transition.updateAlpha(layer: snapshot.layer, alpha: 0.0, delay: delay)
                    transition.updateTransformScale(layer: snapshot.layer, scale: 0.0, delay: delay)
                    transition.updatePosition(layer: snapshot.layer, position: CGPoint(x: position.x, y: position.y - size.height / 4.0), delay: delay) { [weak snapshot] _ in
                        snapshot?.removeFromSuperview()
                    }
                }

                textNode.alpha = 0.0
                textNode.position = CGPoint(x: oldPosition.x, y: oldPosition.y + size.height / 4.0)
                textNode.transform = CATransform3DMakeScale(0.0, 0.0, 1.0)

                transition.updateAlpha(node: textNode, alpha: 1.0, delay: delay)
                transition.updateTransformScale(node: textNode, scale: 1.0, delay: delay)
                transition.updateFrameAsPositionAndBounds(
                    node: textNode,
                    frame: CGRect(origin: CGPoint(x: position.x - size.width / 2.0, y: position.y - size.height / 2.0), size: size),
                    delay: delay
                )

                offsetX += size.width

            case let .remove(rect):
                transition.updateAlpha(node: textNode, alpha: 0.0, delay: delay)
                transition.updateTransformScale(node: textNode, scale: 0.0, delay: delay)
                transition.updatePosition(node: textNode, position: CGPoint(x: rect.midX, y: rect.midY - rect.size.width / 4.0), delay: delay) { [weak textNode] _ in
                    textNode?.removeFromSupernode()
                }

            case .none:
                textNode.attributedText = NSAttributedString(string: textNode.attributedText?.string ?? "", font: font, textColor: textColor)

                let size = textNode.measure(CGSize(width: 50.0, height: layout.size.height))
                let position = CGPoint(x: offsetX + size.width / 2.0, y: size.height / 2.0)
                transition.updateFrameAsPositionAndBounds(
                    node: textNode,
                    frame: CGRect(origin: CGPoint(x: position.x - size.width / 2.0, y: position.y - size.height / 2.0), size: size),
                    delay: delay
                )

                offsetX += size.width
            }

            if [.add, .update, .none].contains(mappedNode.action) {
                existedTextIndex += 1
            }
        }

        let containerFrame = CGRect(x: (layout.size.width - offsetX) / 2.0, y: 0.0, width: offsetX, height: layout.size.height)
        transition.updateFrame(node: containerNode, frame: containerFrame)
    }

    // MARK: - Interface

    func setTitle(_ title: String, transition: ContainedViewLayoutTransition) {
        self.title = title
        layout.flatMap { containerLayoutUpdated($0, transition: transition) }
    }

    // MARK: - Private. Help

    private func makeTextNode() -> ASTextNode {
        let textNode = ASTextNode()
        textNode.displaysAsynchronously = false
        textNode.maximumNumberOfLines = 1
        textNode.truncationMode = .byTruncatingTail
        textNode.isOpaque = false
        return textNode
    }

    private func textAction(old: NSAttributedString?, new: String) -> TextAction {
        guard let attributedText = old else { return .add }
        return attributedText.string != new ? .update : .none
    }

    private func color(start: UIColor, end: UIColor, percent: CGFloat) -> UIColor {
        let percent = max(0.0, min(1.0, percent))

        switch percent {
        case 0.0: return start
        case 1.0: return end
        default:
            var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)

            guard start.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) else { return start }
            guard end.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return end }

            return UIColor(
                red: CGFloat(r1 + (r2 - r1) * percent),
                green: CGFloat(g1 + (g2 - g1) * percent),
                blue: CGFloat(b1 + (b2 - b1) * percent),
                alpha: CGFloat(a1 + (a2 - a1) * percent)
            )
        }
    }
}
