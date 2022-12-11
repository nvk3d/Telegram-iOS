import AsyncDisplayKit
import Display
import TelegramPresentationData

private let backgroundLiveOfflineColor: UIColor = UIColor(rgb: 0x949495)
private let backgroundLiveOnlineColor: UIColor = UIColor(rgb: 0xC83D50)

final class StreamChatTitleNode: ASDisplayNode {
    // MARK: - Children

    enum Mode: Equatable {
        // MARK: - Cases

        case online
        case offline
    }

    // MARK: - Properties

    private(set) var mode: Mode = .offline

    private let theme: PresentationTheme

    private var layout: ContainerViewLayout?

    // MARK: - Nodes

    private let titleNode: ASTextNode

    private let liveBackgroundNode: ASDisplayNode
    private let liveNode: ASTextNode

    // MARK: - Init

    init(theme: PresentationTheme) {
        self.theme = theme

        titleNode = ASTextNode()
        titleNode.displaysAsynchronously = false
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.isOpaque = false

        liveBackgroundNode = ASDisplayNode()
        liveBackgroundNode.cornerRadius = 10.0
        liveBackgroundNode.backgroundColor = backgroundLiveOfflineColor

        liveNode = ASTextNode()
        liveNode.displaysAsynchronously = false
        liveNode.maximumNumberOfLines = 1
        liveNode.truncationMode = .byTruncatingTail
        liveNode.isOpaque = false
        liveNode.attributedText = NSAttributedString(string: "LIVE", font: Font.bold(11.0), textColor: UIColor(rgb: 0xffffff))

        super.init()

        addSubnode(titleNode)
        addSubnode(liveBackgroundNode)
        liveBackgroundNode.addSubnode(liveNode)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Life cycle

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.layout = layout

        let interitemMargin: CGFloat = 5.0

        let titleSize = titleNode.measure(CGSize(width: layout.size.width - 140.0, height: layout.size.height))
        let liveSize = liveNode.measure(CGSize(width: layout.size.width - 14.0, height: layout.size.height))
        let liveBackgroundSize = CGSize(width: liveSize.width + 10.0, height: 20.0)

        let commonWidth: CGFloat = titleSize.width + interitemMargin + liveBackgroundSize.width
        let titleFrame = CGRect(
            origin: CGPoint(x: floor((layout.size.width - commonWidth) / 2.0), y: floor(layout.size.height - titleSize.height) / 2.0),
            size: titleSize
        )
        transition.updateFrame(node: titleNode, frame: titleFrame)

        let liveBackgroundFrame = CGRect(
            origin: CGPoint(x: titleFrame.maxX + interitemMargin, y: floor((layout.size.height - liveBackgroundSize.height) / 2.0) + 1.0),
            size: liveBackgroundSize
        )
        transition.updateFrame(node: liveBackgroundNode, frame: liveBackgroundFrame)

        let liveFrame = CGRect(
            origin: CGPoint(x: floor((liveBackgroundSize.width - liveSize.width) / 2.0), y: (liveBackgroundSize.height - liveSize.height) / 2.0),
            size: liveSize
        )
        transition.updateFrame(node: liveNode, frame: liveFrame)
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

        titleNode.attributedText = NSAttributedString(string: title, font: Font.bold(17.0), textColor: UIColor(rgb: 0xffffff))
        layout.flatMap { containerLayoutUpdated($0, transition: transition) }
    }

    func setMode(_ mode: Mode, transition: ContainedViewLayoutTransition) {
        guard mode != self.mode else { return }

        if case let .animated(duration, curve) = transition, mode == .online, liveBackgroundNode.layer.animation(forKey: "bounce") == nil {
            let animation = liveBackgroundNode.layer.makeAnimation(from: NSNumber(value: Float(1.0)), to: NSNumber(value: Float(1.2)), keyPath: "transform.scale", timingFunction: curve.timingFunction, duration: duration)
            animation.autoreverses = true
            liveBackgroundNode.layer.add(animation, forKey: "bounce")
        }

        self.mode = mode
        transition.updateBackgroundColor(node: liveBackgroundNode, color: mode == .online ? backgroundLiveOnlineColor : backgroundLiveOfflineColor)
    }
}
