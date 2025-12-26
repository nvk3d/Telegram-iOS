import CoreImage
import Display
import Metal
import QuartzCore
import UIKit

open class GlassLozengeLensLayer: GlassLozengeLayer {
    // MARK: - Properties

    private var animator: ConstantDisplayLinkAnimator?
    private var internalAnimatorCall = false

    // MARK: - Init

    public override init(style: GlassStyle) {
        super.init(style: style)
    }

    public override init(layer: Any) {
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animator?.invalidate()
    }

    // MARK: - Interface

    open func animateViewport(with transition: ContainedViewLayoutTransition) {
        animator?.invalidate()

        guard case let .animated(duration, _) = transition else {
            return
        }
        guard let context = GlassLozengeContext.current, let renderLayer = context.renderLayer else {
            return
        }
        guard let previousSourceTexture = self.previousSourceTexture,
              let animationTexture = makeAnimationSourceTexture(previousSourceTexture, context: context) else {
            return
        }

        let beginTime = CACurrentMediaTime()
        animator = ConstantDisplayLinkAnimator { [weak self] in
            guard let self else { return }

            let currentTime = CACurrentMediaTime()
            let animationTime = currentTime - beginTime

            let currentViewport = self.viewport(in: renderLayer)
            self.previousViewport = currentViewport

            if let renderingContext = GlassLozengeRenderingContext(context: context) {
                self.internalAnimatorCall = true
                self.render(renderingContext, with: animationTexture)
                self.internalAnimatorCall = false

                renderingContext.commandBuffer.commit()
                renderingContext.commandBuffer.waitUntilScheduled()
            }

            if animationTime > duration {
                self.animator?.invalidate()
                self.animator = nil
            }
        }
        animator?.isPaused = false
    }

    open override func render(_ context: GlassLozengeRenderingContext, with texture: MTLTexture) {
        if !internalAnimatorCall {
            animator?.invalidate()
            animator = nil
        }
        super.render(context, with: texture)
    }

    // MARK: - Private. Help

    private func makeAnimationSourceTexture(_ previousSourceTexture: MTLTexture, context: GlassLozengeContext) -> MTLTexture? {
        let descriptor: MTLTextureDescriptor = .texture2DDescriptor(pixelFormat: .bgra8Unorm, width: previousSourceTexture.width, height: previousSourceTexture.height, mipmapped: false)
        descriptor.usage = [.shaderRead]

        guard let processingTexture = context.device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            return nil
        }
        guard let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }

        blitCommandEncoder.copy(
            from: previousSourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: previousSourceTexture.width, height: previousSourceTexture.height, depth: previousSourceTexture.depth),
            to: processingTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitCommandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilScheduled()

        return processingTexture
    }
}
