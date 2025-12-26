import CoreImage
import Display
import Metal
import QuartzCore
import UIKit

public let kGlassLozengeIgnorableLayer = "__glassLozengeIgnorable__"

public struct GlassLozengeContextRenderUpdate {
    // MARK: - Properties

    public let context: GlassLozengeRenderingContext
    public let texture: MTLTexture
}

public protocol GlassLozengeRenderTarget: AnyObject {
    // MARK: - Properties

    var paused: Bool { get set }

    // MARK: - Interface

    func needToRender(in renderLayer: CALayer) -> Bool

    func render(_ context: GlassLozengeRenderingContext, with texture: MTLTexture)
    func viewport(in renderLayer: CALayer) -> CGRect
}

public final class GlassLozengeContext {
    // MARK: - Children

    private final class WeakRenderTarget {
        // MARK: - Properties

        weak var renderTarget: GlassLozengeRenderTarget?

        // MARK: - Init

        init(renderTarget: GlassLozengeRenderTarget) {
            self.renderTarget = renderTarget
        }
    }

    // MARK: - Static. Properties

    public static var current: GlassLozengeContext?

    // MARK: - Properties

    public let id: String

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let contentsScale: CGFloat
    public let context: CIContext
    private let maximumFrameTime: TimeInterval
    private let renderer: GlassLozengeLayerRenderer

    public private(set) var renderLayer: CALayer?
    private var snapshotTree: SnapshotRenderTree?
    private var ignoreNextRender = false

    private var renderTargets: [WeakRenderTarget] = []
    private var renderTargetIds: Set<ObjectIdentifier> = []

    private var previousTime: CFTimeInterval = 0.0
    private var displayLink: SharedDisplayLinkDriverLink?

    // MARK: - Init

    public init?(id: String = UUID().uuidString, device: MTLDevice? = nil, scale: CGFloat = UIScreen.main.scale) {
        assert(Self.current == nil)

        guard Self.current == nil, let device = device ?? MTLCreateSystemDefaultDevice() else {
            return nil
        }

        self.id = id
        self.device = device
        self.contentsScale = scale
        self.maximumFrameTime = 1.0 / TimeInterval(UIScreen.main.maximumFramesPerSecond) / 2.0 + 0.002

        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue
        self.context = CIContext(mtlDevice: device)
        self.renderer = GlassLozengeLayerRenderer(device: device, commandQueue: commandQueue, contentsScale: scale)

        displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
            guard let self else { return }
            self.displayLinkAction()
        })

        Self.current = self
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Interface

    public func add(_ renderTarget: GlassLozengeRenderTarget) {
        if !renderTargets.contains(where: { $0.renderTarget === renderTarget }) {
            renderTargets.append(WeakRenderTarget(renderTarget: renderTarget))
        } else {
            assertionFailure()
        }
    }

    public func remove(_ renderTarget: GlassLozengeRenderTarget) {
        for index in 0 ..< renderTargets.count {
            if renderTargets[index] === renderTarget {
                renderTargets.remove(at: index)
                break
            }
        }
    }

    public func setRenderLayer(_ layer: CALayer) {
        guard renderLayer !== layer else {
            return
        }

        renderLayer = layer
        snapshotTree = SnapshotRenderTree(contentsScale: contentsScale, renderLayer: layer)

        // note: for some reason renderer draws previous texture one time after set new render layer
        ignoreNextRender = true
    }

    // MARK: - Private. Actions

    private func displayLinkAction() {
        let time = CACurrentMediaTime()
        if previousTime > maximumFrameTime {
            //print("drop frame")
            previousTime = 0.0
            return
        }
        defer { previousTime = CACurrentMediaTime() - time /*; print("context time: \(previousTime)")*/ }
        render()
    }

    // MARK: - Private. Render

    private func render() {
        guard let snapshotTree, snapshotTree.hasUpdates() else {
            return
        }
        guard let renderingContext = GlassLozengeRenderingContext(context: self) else {
            return
        }

        let (renderTargets, viewports) = filterRenderTargets()
        if viewports.isEmpty {
            return
        }

        snapshotTree.setViewports(viewports)

        let snapshot = snapshotTree.makeSnapshot()
        guard let texture = renderer.render(snapshot) else {
            return
        }

        if !ignoreNextRender {
            for renderTarget in renderTargets {
                renderTarget.render(renderingContext, with: texture)
            }
        }
        ignoreNextRender = false

        renderingContext.commandBuffer.commit()
        renderingContext.commandBuffer.waitUntilScheduled()
    }

    // MARK: - Private. Help

    private func filterRenderTargets() -> ([GlassLozengeRenderTarget], [CGRect]) {
        guard let renderLayer else { return ([], []) }

        var renderTargets: [GlassLozengeRenderTarget] = []
        var viewports: [CGRect] = []
        var index = self.renderTargets.count - 1
        //print("render target count: \(self.renderTargets.count)")

        while index >= 0 {
            let weakTarget = self.renderTargets[index]
            if weakTarget.renderTarget == nil {
                self.renderTargets.remove(at: index)
                index -= 1
                continue
            }
            if let renderTarget = weakTarget.renderTarget, !renderTarget.paused, renderTarget.needToRender(in: renderLayer) {
                let viewport = renderTarget.viewport(in: renderLayer)
                if !viewport.size.equalTo(.zero) {
                    renderTargets.append(renderTarget)
                    viewports.append(viewport)
                }
            }
            index -= 1
        }

        //print("render target count: \(renderTargets.count)")
        return (renderTargets, viewports)
    }
}
