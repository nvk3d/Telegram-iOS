import AsyncDisplayKit
import Display

final class CallControllerCustomToastNode: ASDisplayNode {
    // MARK: - Nodes

    private let effectView: UIVisualEffectView
    private let textNode: ImmediateTextNode

    // MARK: - Init

    override init() {
        effectView = UIVisualEffectView()
        effectView.effect = UIBlurEffect(style: .light)
        effectView.isUserInteractionEnabled = false

        textNode = ImmediateTextNode()

        super.init()

        layer.cornerRadius = 15.0
        layer.masksToBounds = true

        view.addSubview(effectView)
        addSubnode(textNode)
    }

    // MARK: - Life cycle

    func updateLayout(_ constrainedSize: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        let textSize = textNode.updateLayout(constrainedSize)
        let height: CGFloat = max(30.0, textSize.height + 10.0)
        let textFrame = CGRect(x: 12.0, y: (height - textSize.height) / 2.0, width: textSize.width, height: height)
        transition.updateFrame(node: textNode, frame: textFrame)
        let size = CGSize(width: textSize.width + 24.0, height: height)
        transition.updateFrame(view: effectView, frame: CGRect(origin: .zero, size: size))
        return size
    }

    // MARK: - Interface

    func update(title: String) {
        textNode.attributedText = NSAttributedString(string: title, font: Font.regular(16.0), textColor: .white, paragraphAlignment: .center)
    }
}
