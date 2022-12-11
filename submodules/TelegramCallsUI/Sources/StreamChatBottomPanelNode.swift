import AsyncDisplayKit
import Display
import TelegramPresentationData

final class StreamChatBottomPanelNode: ASDisplayNode {
    // MARK: - Properties

    var shareTapped: (() -> Void)?
    var expandTapped: (() -> Void)?
    var leaveTapped: (() -> Void)?

    private let presentationData: PresentationData

    private var layout: ContainerViewLayout?

    // MARK: - Nodes

    private let shareButton: CallControllerButtonItemNode
    private let expandButton: CallControllerButtonItemNode
    private let leaveButton: CallControllerButtonItemNode

    // MARK: - Init

    init(presentationData: PresentationData) {
        self.presentationData = presentationData

        shareButton = CallControllerButtonItemNode()
        expandButton = CallControllerButtonItemNode()
        leaveButton = CallControllerButtonItemNode()

        super.init()

        setupNodes()
    }

    // MARK: - Life cycle

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.layout = layout

        let buttons: [CallControllerButtonItemNode] = [shareButton, expandButton, leaveButton]

        let buttonSize = CGSize(width: 56.0, height: 60.0)

        let sideMargin: CGFloat = 45.0
        let interbuttonMargin: CGFloat = (layout.size.width - sideMargin * 2.0 - buttonSize.width * CGFloat(buttons.count)) / CGFloat(max(1, buttons.count - 1))

        let shareFrame = CGRect(
            origin: CGPoint(x: sideMargin, y: 0.0),
            size: buttonSize
        )
        transition.updateFrame(node: shareButton, frame: shareFrame)
        shareButton.update(
            size: buttonSize,
            content: CallControllerButtonItemNode.Content(appearance: .gradientDiagonal([0x6b93ff, 0x8878ff], 0.3), image: .share),
            text: presentationData.strings.VoiceChat_ShareShort,
            transition: transition
        )

        let expandFrame = CGRect(
            origin: CGPoint(x: shareFrame.maxX + interbuttonMargin, y: 0.0),
            size: buttonSize
        )
        transition.updateFrame(node: expandButton, frame: expandFrame)
        expandButton.update(
            size: buttonSize,
            content: CallControllerButtonItemNode.Content(appearance: .gradientDiagonal([0x8878ff, 0xe46ace], 0.3), image: .expand),
            text: "expand",
            transition: transition
        )

        let leaveFrame = CGRect(
            origin: CGPoint(x: expandFrame.maxX + interbuttonMargin, y: 0.0),
            size: buttonSize
        )
        transition.updateFrame(node: leaveButton, frame: leaveFrame)
        leaveButton.update(
            size: buttonSize,
            content: CallControllerButtonItemNode.Content(appearance: .color(.custom(0xff3b30, 0.3)), image: .cancel),
            text: presentationData.strings.VoiceChat_Leave,
            transition: transition
        )

        // Gradient colors
//        UIColor(rgb: 0x0077ff),
//        UIColor(rgb: 0x6b93ff),
//        UIColor(rgb: 0x8878ff),
//        UIColor(rgb: 0xe46ace)
    }

    // MARK: - Private. Actions

    @objc
    private func shareButtonAction(_ sender: CallControllerButtonItemNode) {
        shareTapped?()
    }

    @objc
    private func expandButtonAction(_ sender: CallControllerButtonItemNode) {
        expandTapped?()
    }

    @objc
    private func leaveButtonAction(_ sender: CallControllerButtonItemNode) {
        leaveTapped?()
    }

    // MARK: - Private. Setup

    private func setupNodes() {
        shareButton.addTarget(self, action: #selector(shareButtonAction(_:)), forControlEvents: .touchUpInside)
        addSubnode(shareButton)

        expandButton.addTarget(self, action: #selector(expandButtonAction(_:)), forControlEvents: .touchUpInside)
        addSubnode(expandButton)

        leaveButton.addTarget(self, action: #selector(leaveButtonAction(_:)), forControlEvents: .touchUpInside)
        addSubnode(leaveButton)
    }
}
