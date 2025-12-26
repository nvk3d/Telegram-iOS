import CoreImage
import Metal
import MetalPerformanceShaders
import QuartzCore
import UIKit

final class GlassLozengeLayerRenderer {
    // MARK: - Properties

    private let device: MTLDevice
    private let context: CIContext
    private let commandQueue: MTLCommandQueue
    private let contentsScale: CGFloat
    private let renderer: CARenderer

    private var currentTexture: MTLTexture?

    // MARK: - Init

    init(device: MTLDevice, commandQueue: MTLCommandQueue, contentsScale: CGFloat) {
        self.device = device
        self.commandQueue = commandQueue
        self.contentsScale = contentsScale
        self.context = CIContext(mtlDevice: device)

        let textureDescriptor: MTLTextureDescriptor = .texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 100, height: 100, mipmapped: false)
        textureDescriptor.usage = [.shaderWrite, .renderTarget]
        renderer = CARenderer(mtlTexture: device.makeTexture(descriptor: textureDescriptor)!, options: [kCARendererMetalCommandQueue: commandQueue])
    }

    // MARK: - Init

    func render(_ layer: CALayer) -> MTLTexture? {
        guard !layer.bounds.size.equalTo(.zero) else {
            return nil
        }
        
        let targetHeight = Int(layer.bounds.height * contentsScale)
        let targetWidth = Int(layer.bounds.width * contentsScale)

        var processingTexture: MTLTexture
        if let currentTexture, currentTexture.width == targetWidth, currentTexture.height == targetHeight {
            processingTexture = currentTexture
        } else {
            let textureDescriptor: MTLTextureDescriptor = .texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: targetWidth,
                height: targetHeight,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead, .renderTarget]
            guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                return nil
            }
            processingTexture = texture
            self.currentTexture = texture
        }

        renderer.setDestination(processingTexture)

        renderer.layer = layer
        renderer.bounds = CGRect(origin: .zero, size: CGSize(width: layer.bounds.width * contentsScale, height: layer.bounds.height * contentsScale))
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.render()
        renderer.endFrame()

        return processingTexture
    }

    func clean() {
        currentTexture = nil
    }
}
