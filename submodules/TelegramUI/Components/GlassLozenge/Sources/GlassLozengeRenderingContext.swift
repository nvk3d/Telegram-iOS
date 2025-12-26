import Metal

public final class GlassLozengeRenderingContext {
    // MARK: - Properties

    public let context: GlassLozengeContext
    public let commandBuffer: MTLCommandBuffer

    // MARK: - Init

    init?(context: GlassLozengeContext) {
        self.context = context
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            return nil
        }
        self.commandBuffer = commandBuffer
    }
}
