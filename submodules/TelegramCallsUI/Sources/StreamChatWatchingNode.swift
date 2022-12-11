import AsyncDisplayKit
import Display
import TelegramPresentationData

final class StreamChatWatchingNode: ASDisplayNode {
    // MARK: - Properties

    private let theme: PresentationTheme

    private var layout: ContainerViewLayout?

    // MARK: - Nodes

    private let titleNode: ASTextNode
    private let subtitleNode: ASTextNode

    // MARK: - Init

    init(theme: PresentationTheme) {
        self.theme = theme

        titleNode = ASTextNode()
        titleNode.displaysAsynchronously = false
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.isOpaque = false

        subtitleNode = ASTextNode()
        subtitleNode.displaysAsynchronously = false
        subtitleNode.maximumNumberOfLines = 1
        subtitleNode.truncationMode = .byTruncatingTail
        subtitleNode.isOpaque = false

        super.init()

        setupNodes()
    }

    // MARK: - Life cycle

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.layout = layout

        let titleSize = titleNode.measure(layout.size)
        let subtitleSize = subtitleNode.measure(layout.size)

        let contentHeight: CGFloat = titleSize.height + subtitleSize.height

        let titleFrame = CGRect(
            origin: CGPoint(x: (layout.size.width - titleSize.width) / 2.0, y: (layout.size.height - contentHeight) / 2.0),
            size: titleSize
        )
        transition.updateFrame(node: titleNode, frame: titleFrame)

        let subtitleFrame = CGRect(
            origin: CGPoint(x: (layout.size.width - subtitleSize.width) / 2.0, y: titleFrame.maxY),
            size: subtitleSize
        )
        transition.updateFrame(node: subtitleNode, frame: subtitleFrame)
    }

    // MARK: - Interface

    func setTitle(_ title: String, transition: ContainedViewLayoutTransition) {
        if case .animated = transition, title != titleNode.attributedText?.string, let snapshotView = titleNode.view.snapshotContentTree() {
            snapshotView.frame = titleNode.frame
            view.addSubview(snapshotView)

            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false) { [weak snapshotView] _ in
                snapshotView?.removeFromSuperview()
            }

            titleNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        }

        titleNode.attributedText = NSAttributedString(string: title, font: Font.bold(48.0), textColor: UIColor(rgb: 0xffffff))
        layout.flatMap { containerLayoutUpdated($0, transition: transition) }
    }

    func setSubtitle(_ subtitle: String, transition: ContainedViewLayoutTransition) {
        if case .animated = transition, subtitle != subtitleNode.attributedText?.string, let snapshotView = subtitleNode.view.snapshotContentTree() {
            snapshotView.frame = subtitleNode.frame
            view.addSubview(snapshotView)

            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false) { [weak snapshotView] _ in
                snapshotView?.removeFromSuperview()
            }

            subtitleNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        }

        subtitleNode.attributedText = NSAttributedString(string: subtitle, font: Font.bold(14.0), textColor: UIColor(rgb: 0xffffff))
        layout.flatMap { containerLayoutUpdated($0, transition: transition) }
    }

    // MARK: - Private. Setup

    private func setupNodes() {
        addSubnode(titleNode)
        addSubnode(subtitleNode)
    }
}
