import AVFoundation
import Display
import simd
import QuartzCore
import UIKit

final class SnapshotRenderTree {
    // MARK: - Children

    struct AdditionalFramesState {
        // MARK: - Properties

        var current: Int
        let target: Int
    }

    // MARK: - Properties

    private let contentsScale: CGFloat
    private let renderLayer: CALayer

    private var renderLayoutHash: Int?
    private var additionalFramesState: AdditionalFramesState?

    private var viewports: [CGRect] = []

    // MARK: - Init

    init(contentsScale: CGFloat, renderLayer: CALayer) {
        self.contentsScale = contentsScale
        self.renderLayer = renderLayer
    }

    // MARK: - Interface

    func hasUpdates() -> Bool {
        // note: gifs, live emojis has no layout update for hash
        //_hasUpdates(in: renderLayer)
        true
    }

    func setNeedsUpdate() {
        additionalFramesState = AdditionalFramesState(current: 0, target: 10)
    }

    func setViewports(_ viewports: [CGRect]) {
        self.viewports = viewports
    }

    func makeSnapshot() -> CALayer {
        // renderLayoutHash = (renderLayer.presentation() ?? renderLayer).value(forKey: "_layoutHash") as? Int
        let snapshot = makeSnapshot(renderLayer)
        snapshot.contentsScale = contentsScale
        snapshot.isGeometryFlipped = true
        snapshot.rasterizationScale = contentsScale
        snapshot.transform = CATransform3DScale(CATransform3DIdentity, 1.0, -1.0, 1.0)  // renderer has different axis
        snapshot.sublayerTransform = CATransform3DScale(snapshot.sublayerTransform, contentsScale, contentsScale, 1.0)
        snapshot.position = CGPoint(x: renderLayer.bounds.width / 2.0 * contentsScale, y: renderLayer.bounds.height / 2.0 * contentsScale)
        snapshot.masksToBounds = false
        return snapshot
    }

    // MARK: - Private. Help

    private func _hasUpdates(in layer: CALayer) -> Bool {
        let source = layer.presentation() ?? layer
        if let layoutHash = source.value(forKey: "_layoutHash") as? Int, renderLayoutHash != layoutHash {
            if additionalFramesState != nil {
                additionalFramesState?.current = 0
            } else {
                additionalFramesState = AdditionalFramesState(current: 0, target: 10)
            }
            return true
        }
        if let additionalFramesState {
            self.additionalFramesState?.current += 1
            if additionalFramesState.current + 1 >= additionalFramesState.target {
                self.additionalFramesState = nil
            }
            return true
        }
        return false
    }

    private func makeSnapshot(_ layer: CALayer) -> CALayer {
        let source = layer.presentation() ?? layer

        let snapshot: CALayer

        var ignoreSublayers = false
        var isContentOverriden = false
        var overridedContents: Any?

        if layer is AVSampleBufferDisplayLayer {
            ignoreSublayers = true
            snapshot = CALayer()
            isContentOverriden = true
            overridedContents = getVideoContents(layer)
        } else if let metalLayer = layer as? CAMetalLayer {
            isContentOverriden = true
            if let drawable = metalLayer.nextDrawable() {
                overridedContents = drawable.texture.iosurface
            }
            snapshot = CALayer()
        } else if layer.description.contains("PortalLayer"), let snapshotPortal = makePortalSnapshot(layer) {
            snapshot = snapshotPortal
        } else if layer.description.contains("CABackdropLayer"), let snapshotBackdrop = makeBackdropSnapshot(layer) {
            snapshot = snapshotBackdrop
        } else {
            snapshot = CALayer()
        }
        snapshot.actions = layer.actions
        snapshot.allowsGroupOpacity = layer.allowsGroupOpacity
        snapshot.allowsEdgeAntialiasing = layer.allowsEdgeAntialiasing
        snapshot.edgeAntialiasingMask = layer.edgeAntialiasingMask
        snapshot.transform = source.transform
        snapshot.sublayerTransform = source.sublayerTransform
        snapshot.position = source.position
        snapshot.bounds = source.bounds
        snapshot.anchorPoint = source.anchorPoint
        snapshot.contentsGravity = source.contentsGravity
        snapshot.contents = isContentOverriden ? overridedContents : source.contents
        snapshot.contentsScale = source.contentsScale
        snapshot.contentsRect = source.contentsRect
        snapshot.contentsCenter = source.contentsCenter
        snapshot.rasterizationScale = source.rasterizationScale
        snapshot.shouldRasterize = source.shouldRasterize
        snapshot.opacity = source.opacity
        snapshot.filters = source.filters
        snapshot.backgroundFilters = source.backgroundFilters
        snapshot.compositingFilter = source.compositingFilter
        snapshot.backgroundColor = source.backgroundColor
        snapshot.borderColor = source.borderColor
        snapshot.borderWidth = source.borderWidth
        snapshot.cornerRadius = source.cornerRadius
        snapshot.cornerCurve = layer.cornerCurve
        snapshot.masksToBounds = source.masksToBounds
        snapshot.maskedCorners = source.maskedCorners
        snapshot.isOpaque = layer.isOpaque
        snapshot.isDoubleSided = source.isDoubleSided
        snapshot.isGeometryFlipped = source.isGeometryFlipped
        snapshot.isHidden = source.isHidden
        snapshot.shadowColor = source.shadowColor
        snapshot.shadowOffset = source.shadowOffset
        snapshot.shadowOpacity = source.shadowOpacity
        snapshot.shadowRadius = source.shadowRadius
        snapshot.shadowPath = source.shadowPath
        if let mask = source.mask {
            snapshot.mask = makeSnapshot(mask)
        }
        if let contentsMaximumDesiredEDR = source.value(forKey: "contentsMaximumDesiredEDR") {
            snapshot.setValue(contentsMaximumDesiredEDR, forKey: "contentsMaximumDesiredEDR")
        }
        if let contentsSwizzle = source.value(forKey: "contentsSwizzle") {
            snapshot.setValue(contentsSwizzle, forKey: "contentsSwizzle")
        }
        snapshot.layerTintColor = source.layerTintColor

        if !ignoreSublayers {
            for sublayer in layer.sublayers ?? [] {
                guard !sublayer.isHidden, sublayer.opacity > .ulpOfOne, sublayer.name != kGlassLozengeIgnorableLayer else {
                    continue
                }
                if let glassLayer = sublayer as? GlassLozengeLayer, !glassLayer.paused {
                    break
                }
                if intersectsRenderViewports(sublayer) {
                    let sublayerSnapshot = makeSnapshot(sublayer)
                    snapshot.addSublayer(sublayerSnapshot)
                }
            }
        }

        return snapshot
    }

    private func makeBackdropSnapshot(_ layer: CALayer) -> CALayer? {
        if let backdropClass = NSClassFromString("CABackdropLayer") as AnyObject as? NSObjectProtocol,
           let backdropAllocated = backdropClass.perform(NSSelectorFromString("alloc")).takeUnretainedValue() as? NSObject,
           let backdropSnapshot = backdropAllocated.perform(NSSelectorFromString("init")).takeUnretainedValue() as? CALayer {
            backdropSnapshot.setValue(layer.value(forKey: "scale"), forKey: "scale")
            return backdropSnapshot
        }
        return nil
    }

    private func makePortalSnapshot(_ layer: CALayer) -> CALayer? {
        if let sourceLayer = layer.value(forKey: "sourceLayer") as? CALayer {
            let snapshot = CALayer()
            let sourcePosition = sourceLayer.superlayer?.convert(sourceLayer.position, to: layer) ?? sourceLayer.position
            let sourceSnapshot = makeSnapshot(sourceLayer)
            sourceSnapshot.opacity = 1.0
            sourceSnapshot.position = sourcePosition
            snapshot.addSublayer(sourceSnapshot)
            return snapshot
        }
        return nil
    }

    private func getVideoContents(_ layer: CALayer) -> Any? {
        let getContents: (CVPixelBuffer) -> Any = { buffer in
            if let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() {
                return surface
            } else {
                return buffer
            }
        }

        if layer.description.contains("MediaPlayerNodeLayer"),
           let renderTarget = layer.value(forKey: "renderTarget") as? NSObject,
           let buffer = renderTarget.value(forKey: "displayedPixelBuffer") {
            return getContents(buffer as! CVPixelBuffer)
        } else if let renderer = layer.value(forKey: "sampleBufferRenderer") as? NSObject,
                  renderer.responds(to: NSSelectorFromString("copyDisplayedPixelBuffer")),
                  let buffer = renderer.perform(NSSelectorFromString("copyDisplayedPixelBuffer")) {
            defer { buffer.release() }
            return getContents(buffer.takeUnretainedValue() as! CVPixelBuffer)
        }
        return nil
    }

    private func intersectsRenderViewports(_ layer: CALayer) -> Bool {
        let sublayerFrameInRender = layer.superlayer?.convert(layer.frame, to: renderLayer) ?? layer.frame
        for viewport in viewports {
            if viewport.intersects(sublayerFrameInRender) {
                return true
            }
        }
        return false
    }
}
