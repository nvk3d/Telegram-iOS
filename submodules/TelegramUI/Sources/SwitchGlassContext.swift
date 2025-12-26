import Display
import GlassLozenge
import QuartzCore
import UIKit

final class SwitchGlassContext: SwitchNodeAdditionalContext {
    // MARK: - Layers

    private let glassLayer: GlassLozengeLayer

    // MARK: - Nodes

    private weak var targetNode: SwitchNode?

    // MARK: - Init

    init(targetNode: SwitchNode) {
        self.targetNode = targetNode

        glassLayer = GlassLozengeLayer(style: .lozenge)
        glassLayer.opacity = 0.0
        glassLayer.lozengeParams = glassLayer.lozengeParams.with(refraction: 1.05)
    }

    deinit {
        glassLayer.removeFromSuperlayer()
    }

    // MARK: - Interface

    func actionImageUpdated(_ actionView: UIView) {
        guard let targetNode else { return }

        let glassSize = CGSize(width: (targetNode.bounds.height + 4.0) * 1.2, height: targetNode.bounds.height + 4.0)
        let actionPosition = targetNode.view.convert(targetNode.actionImagePosition ?? .zero, to: targetNode.view.superview)
        let glassFrame = CGRect(origin: CGPoint(x: actionPosition.x - glassSize.width / 2.0, y: actionPosition.y - glassSize.height / 2.0), size: glassSize)
        glassLayer.position = CGPoint(x: glassFrame.midX, y: glassFrame.midY)
        glassLayer.bounds = CGRect(origin: .zero, size: glassSize)
        glassLayer.update(size: glassLayer.bounds.size)
    }

    func interactionBegan() {
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .slide)
        targetNode?.setActionImageHidden(true, transition: transition)
        transition.updateAlpha(layer: glassLayer, alpha: 1.0, beginWithCurrentState: glassLayer.animation(forKey: "opacity") != nil)
        transition.updateTransformScale(layer: glassLayer, scale: 1.0)
    }

    func interactionEnded() {
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .slide)
        targetNode?.setActionImageHidden(false, transition: transition)
        transition.updateAlpha(layer: glassLayer, alpha: 0.0)

        if let targetView = targetNode?.view {
            let scale = (targetView.bounds.height - 4.0) / (targetView.bounds.height + 4.0)
            transition.updateTransformScale(layer: glassLayer, scale: scale)
        }
    }

    func didMove(to superview: UIView?) {
        if let superview, let targetView = targetNode?.view.superview {
            superview.layer.insertSublayer(glassLayer, above: targetView.layer)
        } else {
            glassLayer.removeFromSuperlayer()
        }
    }
}
