import CoreImage
import Display
import Metal
import QuartzCore
import UIKit

open class GlassLozengeLayer: CAMetalLayer, GlassLozengeRenderTarget {
    // MARK: - Children

    public enum GlassStyle {
        // MARK: - Cases

        case lozenge
        case shader
    }

    public struct LozengeParams {
        // MARK: - Properties

        public let refraction: Double

        // MARK: - Init

        public init(refraction: Double = 1.7) {
            self.refraction = refraction
        }

        // MARK: - Interface

        public func with(refraction: Double? = nil) -> LozengeParams {
            LozengeParams(refraction: refraction ?? self.refraction)
        }
    }

    public struct ShaderParams {
        // MARK: - Properties

        // Refraction area size
        public let refractionDim: Float

        // Refraction vector magnitude (base)
        public let refractionMagnitude: Float

        // Corner radius
        public let cornerRadius: Float

        // Tint color
        public let tintColor: UIColor

        // MARK: - Init

        public init(refractionDim: Float = 0.5, refractionMagnitude: Float = 0.15, cornerRadius: Float = 0.0, tintColor: UIColor = .clear) {
            self.refractionDim = refractionDim
            self.refractionMagnitude = refractionMagnitude
            self.cornerRadius = cornerRadius
            self.tintColor = tintColor
        }

        // MARK: - Interface

        public func with(refractionDim: Float? = nil, refractionMagnitude: Float? = nil, cornerRadius: Float? = nil, tintColor: UIColor? = nil) -> ShaderParams {
            ShaderParams(refractionDim: refractionDim ?? self.refractionDim, refractionMagnitude: refractionMagnitude ?? self.refractionMagnitude, cornerRadius: cornerRadius ?? self.cornerRadius, tintColor: tintColor ?? self.tintColor)
        }
    }

    public enum Params {
        // MARK: - Cases

        case lozenge(LozengeParams)
        case shader(ShaderParams)
    }

    // MARK: - Properties

    public let glassStyle: GlassStyle

    public var lozengeParams = LozengeParams()
    public var shaderParams = ShaderParams()

    open var paused = false {
        didSet {
            if oldValue != paused {
                ignoreNextRender = true
            }
        }
    }
    private var ignoreNextRender = false

    private var filter: CIFilter?
    private var shaderContext: GlassShaderContext?

    internal weak var previousSourceTexture: MTLTexture?
    internal var intermediateTexture: MTLTexture?
    internal var previousViewport: CGRect?

    // MARK: - Init

    public init(style: GlassStyle) {
        self.glassStyle = style

        if style == .lozenge {
            filter = CIFilter(name: "CIGlassLozenge")
        }

        super.init()

        backgroundColor = UIColor.clear.cgColor
        contentsScale = UIScreen.main.scale
        drawsAsynchronously = true
        framebufferOnly = false
        isOpaque = false
        masksToBounds = true
        pixelFormat = .bgra8Unorm
        rasterizationScale = UIScreen.main.scale

        GlassLozengeContext.current?.add(self)
    }

    public override init(layer: Any) {
        glassStyle = .lozenge
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        GlassLozengeContext.current?.remove(self)
    }

    // MARK: - Life cycle

    open func update(size: CGSize) {
        switch glassStyle {
        case .lozenge:
            cornerRadius = min(size.width, size.height) / 2.0
        case .shader:
            cornerRadius = CGFloat(shaderParams.cornerRadius)
        }

        let scaledSize = CGSize(width: floorToScreenPixels(size.width) * contentsScale, height: floorToScreenPixels(size.height) * contentsScale)
        if drawableSize != scaledSize {
            drawableSize = scaledSize
        }
    }

    // MARK: - Interface

    open func needToRender(in layer: CALayer) -> Bool {
        var currentLayer: CALayer? = self
        while let current = currentLayer {
            if current.isHidden || current.opacity < .ulpOfOne {
                return false
            }
            if current === layer {
                return true
            }
            currentLayer = current.superlayer
        }
        return false
    }

    open func render(_ context: GlassLozengeRenderingContext, with texture: MTLTexture) {
        guard !paused else { return }

        if ignoreNextRender {
            ignoreNextRender = false
            return
        }

        previousSourceTexture = texture

//        let time = CACurrentMediaTime()
//        print("lozenge layer time: \(CACurrentMediaTime() - time)")
        
        guard !drawableSize.equalTo(.zero), let drawable = nextDrawable() else {
            return
        }
        guard let renderLayer = context.context.renderLayer else {
            return
        }

        let renderRect = renderLayer.bounds
        let viewport = previousViewport ?? viewport(in: renderLayer)
        let intersection = renderRect.intersection(viewport)
        //print("intersection: \(intersection)")

        if !intersection.minX.isFinite || !intersection.minY.isFinite || !intersection.width.isFinite || !intersection.height.isFinite {
            return
        }

        let sourceOrigin = MTLOrigin(x: Int(floorToScreenPixels(intersection.minX) * contentsScale), y: Int(floorToScreenPixels(intersection.minY) * contentsScale), z: 0)
        let sourceSize = MTLSize(
            width: min(drawable.texture.width, Int(floorToScreenPixels(intersection.width) * contentsScale)),
            height: min(drawable.texture.height, Int(floorToScreenPixels(intersection.height) * contentsScale)),
            depth: 1
        )

        if sourceSize.width == 0 || sourceSize.height == 0 || sourceOrigin.x < 0 || sourceOrigin.y < 0 || sourceOrigin.x + sourceSize.width > texture.width || sourceOrigin.y + sourceSize.height > texture.height {
            return
        }

        guard let blitCommandEncoder = context.commandBuffer.makeBlitCommandEncoder() else {
            return
        }

        let processingTexture: MTLTexture
        if let intermediateTexture, intermediateTexture.width == drawable.texture.width, intermediateTexture.height == drawable.texture.height {
            processingTexture = intermediateTexture
        } else {
            let descriptor: MTLTextureDescriptor = .texture2DDescriptor(pixelFormat: .bgra8Unorm, width: drawable.texture.width, height: drawable.texture.height, mipmapped: false)
            descriptor.usage = [.shaderRead]
            processingTexture = context.context.device.makeTexture(descriptor: descriptor)!
            self.intermediateTexture = processingTexture
        }

        blitCommandEncoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: sourceOrigin,
            sourceSize: sourceSize,
            to: processingTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitCommandEncoder.endEncoding()

        switch glassStyle {
        case .lozenge:
            processTextureLozenge(processingTexture, drawable: drawable, context: context)
        case .shader:
            processTextureShader(processingTexture, drawable: drawable, context: context)
        }

        context.commandBuffer.present(drawable)
    }

    open func viewport(in renderLayer: CALayer) -> CGRect {
        let source = presentation() ?? self
        let sourcePosition = superlayer?.convert(source.position, to: renderLayer) ?? source.position
        let viewport = CGRect(
            origin: CGPoint(x: sourcePosition.x - source.bounds.width / 2.0, y: sourcePosition.y - source.bounds.height / 2.0),
            size: source.bounds.size
        )
        previousViewport = viewport
        return viewport
    }

    // MARK: - Private. Process

    private func processTextureLozenge(_ processingTexture: MTLTexture, drawable: CAMetalDrawable, context: GlassLozengeRenderingContext) {
        guard let filter else {
            return
        }

        let scaledSize = drawableSize
        let radius = min(scaledSize.width, scaledSize.height) / 2.0

        let point0 = CGPoint(x: radius, y: radius)
        let point1 = CGPoint(x: scaledSize.width - radius, y: scaledSize.height - radius)

        filter.setValue(radius as NSNumber, forKey: "inputRadius")
        filter.setValue(lozengeParams.refraction as NSNumber, forKey: "inputRefraction")
        filter.setValue(CIVector(cgPoint: point0), forKey: "inputPoint0")
        filter.setValue(CIVector(cgPoint: point1), forKey: "inputPoint1")
        filter.setValue(CIImage(mtlTexture: processingTexture), forKey: "inputImage")

        guard let outputImage = filter.outputImage?.oriented(.downMirrored) else {
            assertionFailure("glass filter failed")
            return
        }

        let targetTexture = drawable.texture

        let renderBounds = CGRect(origin: .zero, size: CGSize(width: targetTexture.width, height: targetTexture.height))
        context.context.context.render(outputImage, to: targetTexture, commandBuffer: context.commandBuffer, bounds: renderBounds, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    private func processTextureShader(_ processingTexture: MTLTexture, drawable: CAMetalDrawable, context: GlassLozengeRenderingContext) {
        guard let shaderContext = shaderContext ?? GlassShaderContext(device: context.context.device, scale: contentsScale) else {
            assertionFailure("can't create shader context")
            return
        }

        //let refractionKoef = UIDevice.current.orientation.isLandscape ? 0.02 : 0.015
//        let params = GlassShaderContext.Params(
//            blurSteps: blurSteps,
//            cornerRadius: cornerRadius * contentsScale,
//            position: CGPoint(x: bounds.midX * contentsScale, y: bounds.midY * contentsScale),
//            size: CGSize(width: bounds.width * contentsScale, height: bounds.height * contentsScale),
//            refraction: 0.1, //refraction * refractionKoef,
//            tintColor: .clear // tmp
//        )
        shaderContext.process(processingTexture, drawable: drawable, context: context, params: shaderParams)
    }
}
