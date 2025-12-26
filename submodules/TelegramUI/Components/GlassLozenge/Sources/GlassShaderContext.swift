import Metal
import GlassLozengeUtils
import UIKit

private final class Vertices {
    // MARK: - Properties

    var count: Int {
        vertices.count
    }

    private let vertices: [GlassLozengeVertex]
    private let length: Int
    private var memory: UnsafeMutableRawPointer

    // MARK: - Init

    init(vertices: [GlassLozengeVertex]) {
        self.vertices = vertices
        length = vertices.count * MemoryLayout<GlassLozengeVertex>.size
        memory = malloc(length)

        var vertices = vertices
        memcpy(memory, &vertices, length);
    }

    deinit {
        free(memory)
    }

    // MARK: - Interface

    func encode(with commandEncoder: MTLRenderCommandEncoder) {
        commandEncoder.setVertexBytes(memory, length: length, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: count)
    }

    // MARK: - Static. Interface

    static func square(in rect: CGRect) -> Vertices {
        let l = Float(rect.minX)
        let r = Float(rect.maxX)
        let t = Float(rect.minY)
        let b = Float(rect.maxY)
        return Vertices(vertices: [
            GlassLozengeVertex(position: SIMD4(l, t, 0, 1), textureCoordinate: SIMD2(0, 1)),
            GlassLozengeVertex(position: SIMD4(r, t, 0, 1), textureCoordinate: SIMD2(1, 1)),
            GlassLozengeVertex(position: SIMD4(l, b, 0, 1), textureCoordinate: SIMD2(0, 0)),
            GlassLozengeVertex(position: SIMD4(r, b, 0, 1), textureCoordinate: SIMD2(1, 0))
        ])
    }
}

final class GlassShaderContext {
    // MARK: - Properties

    private let scale: CGFloat

    private let renderPipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState

    // MARK: - Init

    init?(device: MTLDevice, scale: CGFloat) {
        self.scale = scale

        let mainBundle = Bundle(for: GlassShaderContext.self)
        guard let bundlePath = mainBundle.path(forResource: "GlassLozengeBundle", ofType: "bundle"), let bundle = Bundle(path: bundlePath) else {
            assertionFailure("can't find bundle")
            return nil
        }
        guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
            assertionFailure("can't find shader library")
            return nil
        }

        let colorAttachmentDescriptor = MTLRenderPipelineColorAttachmentDescriptor()
        colorAttachmentDescriptor.pixelFormat = .bgra8Unorm
        colorAttachmentDescriptor.isBlendingEnabled = false

        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "glassVertex")
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "glassFragment")
        renderPipelineDescriptor.colorAttachments[0] = colorAttachmentDescriptor
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.rasterSampleCount = 1

        guard let renderPipelineState = try? device.makeRenderPipelineState(descriptor: renderPipelineDescriptor, options: .argumentInfo, reflection: nil) else {
            assertionFailure("can't create render pipeline state")
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero

        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            assertionFailure("can't create sampler state")
            return nil
        }

        self.renderPipelineState = renderPipelineState
        self.samplerState = samplerState
    }

    // MARK: - Interface

    func process(_ processingTexture: MTLTexture, drawable: CAMetalDrawable, context: GlassLozengeRenderingContext, params: GlassLozengeLayer.ShaderParams) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandEncoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            assertionFailure("can't create render command encoder")
            return
        }

        let vertices: Vertices = .square(in: CGRect(x: -1, y: -1, width: 2, height: 2))

        commandEncoder.setRenderPipelineState(renderPipelineState)

        commandEncoder.setVertexTexture(processingTexture, index: 0)
        commandEncoder.setVertexSamplerState(samplerState, index: 0)

        commandEncoder.setFragmentTexture(processingTexture, index: 0)
        commandEncoder.setFragmentSamplerState(samplerState, index: 0)

        let floatTextureHeight = Float(processingTexture.height)

        var cornerRadius = params.cornerRadius * Float(scale)
        var tintColor = params.tintColor.getComponents()
        var refractionDim = min(floatTextureHeight * params.refractionDim, 18.0 * Float(scale)) / floatTextureHeight  // area
        var refractionMag = min(floatTextureHeight * params.refractionMagnitude, 8.0 * Float(scale)) / floatTextureHeight  // border

        commandEncoder.setFragmentBytes(&cornerRadius, length: MemoryLayout.size(ofValue: cornerRadius), index: 0)
        commandEncoder.setFragmentBytes(&tintColor, length: MemoryLayout.size(ofValue: tintColor), index: 1)
        commandEncoder.setFragmentBytes(&refractionDim, length: MemoryLayout.size(ofValue: refractionDim), index: 2)
        commandEncoder.setFragmentBytes(&refractionMag, length: MemoryLayout.size(ofValue: refractionMag), index: 3)

        vertices.encode(with: commandEncoder)

        commandEncoder.endEncoding()
    }
}

private extension UIColor {
    // MARK: - Interface

    func getComponents() -> SIMD4<Float> {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 0.0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            return SIMD4(Float(r), Float(g), Float(b), Float(a))
        }
        var w: CGFloat = 0.0
        if getWhite(&w, alpha: &a) {
            return SIMD4(Float(w), Float(w), Float(w), Float(a))
        }
        return SIMD4(0, 0, 0, 0)
    }
}
