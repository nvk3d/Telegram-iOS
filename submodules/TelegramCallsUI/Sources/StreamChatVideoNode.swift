import AsyncDisplayKit
import AVKit
import AVKit.AVPictureInPictureController_AVSampleBufferDisplayLayerSupport
import Display
import ShimmerEffect
import SwiftSignalKit
import TelegramPresentationData
import TelegramVoip
import UIKit

final class StreamChatVideoNode: ASDisplayNode {
    // MARK: - Children

    enum Mode: Equatable {
        // MARK: - Cases

        case online
        case offline
    }

    // MARK: - Properties

    var isPictureInPictureActive: Bool { pictureInPictureController?.isPictureInPictureActive ?? false }

    var requestAspectUpdated: (() -> Void)?

    var requestBackControllerForPictureInPicture: (() -> Void)?
    var requestClosePictureInPicture: (() -> Void)?
    private var requestedExpansion: Bool = false

    var requestSmoothCornersForPictureInPicture: (() -> Bool)?

    private(set) var mode: Mode = .offline

    private let theme: PresentationTheme
    private let context: VideoRenderingContext

    private var layout: ContainerViewLayout?
    private var isLandscape: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    private var isAspectUpdateRequested: Bool = false
    private var _aspectRatio: CGFloat = 16.0 / 9.0
    private var _cornerRadius: CGFloat = 12.0

    private var pictureInPictureController: AVPictureInPictureController?

    // MARK: - Nodes

    private let imageNode: ASImageNode
    private let backdropBlurredView: StreamChatBlurredView
    private var backdropVideoView: VideoRenderingView?
    private var videoView: VideoRenderingView?

    private let containerNode: ASDisplayNode
    private let blurredView: StreamChatBlurredView

    private var shimmerView: ShimmerEffectForegroundView?
    private var borderView: UIView?
    private var borderMaskView: UIView?
    private var shimmerBorderView: ShimmerEffectForegroundView?

    // MARK: - Init

    init(input: Signal<OngoingGroupCallContext.VideoFrameData, NoError>?, theme: PresentationTheme) {
        self.theme = theme

        context = VideoRenderingContext()

        imageNode = ASImageNode()
        imageNode.contentMode = .scaleAspectFill
        imageNode.displaysAsynchronously = false
        imageNode.displayWithoutProcessing = true

        backdropBlurredView = StreamChatBlurredView(effect: UIBlurEffect(style: .light))
        backdropBlurredView.colorTint = nil
        backdropBlurredView.saturationDeltaFactor = 1.0
        backdropBlurredView.blurRadius = 0.0

        containerNode = ASDisplayNode()
        containerNode.displaysAsynchronously = false

        blurredView = StreamChatBlurredView(effect: UIBlurEffect(style: .light))
        blurredView.colorTint = nil
        blurredView.saturationDeltaFactor = 1.0
        blurredView.blurRadius = 10.0

        super.init()

        setupNodes()
    }

    // MARK: - Life cycle

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.layout = layout

        let isBackdropBlurredHidden: Bool = mode == .offline || isLandscape
        transition.updateAlpha(layer: backdropBlurredView.layer, alpha: isBackdropBlurredHidden ? 0.0 : 1.0)
        backdropVideoView?.isHidden = isLandscape

        transition.updateFrame(node: imageNode, frame: CGRect(origin: .zero, size: layout.size))
        transition.updateFrame(view: backdropBlurredView, frame: CGRect(origin: CGPoint(x: -32.0, y: -32.0), size: CGSize(width: layout.size.width + 64.0, height: layout.size.height + 64.0)))
        transition.updateFrame(node: containerNode, frame: CGRect(origin: .zero, size: layout.size))

        let blurredMaxSide: CGFloat = max(layout.size.width + 2.0, layout.size.height + 2.0)
        transition.updateFrame(view: blurredView, frame: CGRect(
            origin: CGPoint(x: (layout.size.width - blurredMaxSide) / 2.0, y: (layout.size.height - blurredMaxSide) / 2.0),
            size: CGSize(width: blurredMaxSide, height: blurredMaxSide)
        ))

        if let shimmerView = shimmerView, let borderView = borderView, let borderMaskView = borderMaskView, let shimmerBorderView = shimmerBorderView {
            let width: CGFloat = layout.size.width
            let height: CGFloat = layout.size.height
            let shimmerFrame = CGRect(origin: .zero, size: layout.size)

            transition.updateFrame(view: shimmerView, frame: shimmerFrame)
            transition.updateFrame(view: borderView, frame: shimmerFrame)
            transition.updateFrame(view: borderMaskView, frame: shimmerFrame)
            transition.updateFrame(view: shimmerBorderView, frame: shimmerFrame)

            shimmerView.updateAbsoluteRect(CGRect(origin: CGPoint(x: width * 4.0, y: 0.0), size: shimmerFrame.size), within: CGSize(width: width * 9.0, height: height))
            shimmerBorderView.updateAbsoluteRect(CGRect(origin: CGPoint(x: width * 4.0, y: 0.0), size: shimmerFrame.size), within: CGSize(width: width * 9.0, height: height))
        }

        if let videoView = videoView, let backdropVideoView = backdropVideoView {
            if isAspectUpdateRequested, case let .animated(duration, _) = transition {
                isAspectUpdateRequested = false
                animateAspectChanges(
                    start: videoView.frame,
                    startBackdrop: backdropVideoView.frame,
                    end: CGRect(origin: .zero, size: layout.size),
                    endBackdrop: CGRect(origin: .zero, size: layout.size),
                    duration: duration - 0.05
                )
            } else {
                transition.updateFrame(view: backdropVideoView, frame: CGRect(origin: .zero, size: layout.size))
                transition.updateFrame(view: videoView, frame: CGRect(origin: .zero, size: layout.size))
            }
        }
    }

    // MARK: - Interface

    func activatePictureInPicture(smoothCorners: Bool = false, completion: (() -> Void)? = nil) {
        if let pictureInPictureController = pictureInPictureController {
            pictureInPictureController.startPictureInPicture()
            applySmoothCornersToPictureInPicture(smoothCorners ? 12.0 : 0.0)
        }
        completion?()
    }

    func deactivatePictureInPicture(smoothCorners: Bool = false, completion: (() -> Void)? = nil) {
        guard let pictureInPictureController = pictureInPictureController else { return }

        if pictureInPictureController.isPictureInPictureActive {
            requestedExpansion = true

            applySmoothCornersToPictureInPicture(smoothCorners ? 12.0 : 0.0)
            pictureInPictureController.stopPictureInPicture()
        }

        completion?()
    }

    func getAspect() -> CGFloat {
        _aspectRatio
    }

    func imageUpdated(_ image: UIImage?, aspected: Bool = false, transition: ContainedViewLayoutTransition) {
        if case .animated = transition, image != imageNode.image, let snapshotView = imageNode.view.snapshotContentTree() {
            snapshotView.frame = imageNode.frame
            view.insertSubview(snapshotView, aboveSubview: imageNode.view)

            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false) { [weak snapshotView] _ in
                snapshotView?.removeFromSuperview()
            }

            imageNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        }

        if aspected, videoView == nil, let image = image {
            _aspectRatio = image.size.width / image.size.height
        }

        imageNode.image = image
        layout.flatMap { containerLayoutUpdated($0, transition: transition) }
    }

    func videoUpdated(_ signal: Signal<OngoingGroupCallContext.VideoFrameData, NoError>, transition: ContainedViewLayoutTransition) {
        if videoView == nil, let videoView = context.makeView(input: signal, blur: false, forceSampleBufferDisplayLayer: true) {
            videoView.updateIsEnabled(true)
            videoView.setOnFirstFrameReceived { [weak self] aspectRatio in
                self?._aspectRatio = CGFloat(aspectRatio)
                self?.isAspectUpdateRequested = true
                self?.requestAspectUpdated?()
            }
            videoView.layer.cornerRadius = _cornerRadius
            videoView.layer.masksToBounds = true
            self.videoView = videoView
            view.insertSubview(videoView, belowSubview: containerNode.view)

            if let backdropVideoView = context.makeView(input: signal, blur: false) {
                backdropVideoView.updateIsEnabled(true)
                backdropVideoView.layer.cornerRadius = _cornerRadius
                backdropVideoView.layer.masksToBounds = true
                backdropVideoView.clipsToBounds = true
                self.backdropVideoView = backdropVideoView
                view.insertSubview(backdropVideoView, belowSubview: backdropBlurredView)
            }

            setupPictureInPicture(videoView)
        }

        layout.flatMap { containerLayoutUpdated($0, transition: transition) }
    }

    func setMode(_ mode: Mode, transition: ContainedViewLayoutTransition) {
        guard mode != self.mode else { return }

        let isBackdropBlurredHidden = mode == .offline || isLandscape
        ContainedViewLayoutTransition.immediate.updateAlpha(layer: backdropBlurredView.layer, alpha: isBackdropBlurredHidden ? 0.0 : 1.0)

        backdropBlurredView.updateBlurRadius(mode == .online ? 14.0 : 0.0, transition: transition)
        blurredView.updateBlurRadius(mode == .online ? 0.0 : 10.0, transition: transition)
        updateGloss(mode == .offline)

        self.mode = mode
        layout.flatMap { containerLayoutUpdated($0, transition: transition) }

        if !imageNode.isHidden, mode == .online {
            imageNode.isHidden = true
        }
    }

    func updateCornerRadius(_ cornerRadius: CGFloat, transition: ContainedViewLayoutTransition) {
        _cornerRadius = cornerRadius

        transition.updateCornerRadius(node: imageNode, cornerRadius: cornerRadius)

        if let videoView = videoView, let backdropVideoView = backdropVideoView {
            transition.updateCornerRadius(layer: videoView.layer, cornerRadius: cornerRadius)
            transition.updateCornerRadius(layer: backdropVideoView.layer, cornerRadius: cornerRadius)
        }
        transition.updateCornerRadius(node: containerNode, cornerRadius: cornerRadius)

        if let shimmerView = shimmerView, let borderMaskView = borderMaskView {
            transition.updateCornerRadius(layer: shimmerView.layer, cornerRadius: cornerRadius)
            transition.updateCornerRadius(layer: borderMaskView.layer, cornerRadius: cornerRadius)
        }
    }

    // MARK: - Private. Setup

    private func setupNodes() {
        backgroundColor = .clear

        imageNode.layer.masksToBounds = true
        imageNode.layer.cornerRadius = 12.0
        addSubnode(imageNode)

        view.addSubview(backdropBlurredView)

        containerNode.layer.masksToBounds = true
        containerNode.layer.cornerRadius = 12.0
        addSubnode(containerNode)
        containerNode.view.addSubview(blurredView)

        updateGloss(true)
    }

    private func setupPictureInPicture(_ videoView: VideoRenderingView) {
        guard let sampleBufferVideoView = videoView as? SampleBufferVideoRenderingView else { return }
        guard #available(iOSApplicationExtension 15.0, iOS 15.0, *) else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        final class PlaybackDelegateImpl: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
            func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {

            }

            func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
                return CMTimeRange(start: .zero, duration: .positiveInfinity)
            }

            func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
                return false
            }

            func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
            }

            func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
                completionHandler()
            }

            public func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
                return false
            }
        }

        let pictureInPictureController = AVPictureInPictureController(contentSource: AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: sampleBufferVideoView.sampleBufferLayer, playbackDelegate: PlaybackDelegateImpl()))

        pictureInPictureController.delegate = self
        pictureInPictureController.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPictureController.requiresLinearPlayback = true

        self.pictureInPictureController = pictureInPictureController
    }

    // MARK: - Private. Help

    private var displayLinkAnimator: DisplayLinkAnimator?
    private func animateAspectChanges(start: CGRect, startBackdrop: CGRect, end: CGRect, endBackdrop: CGRect, duration: CGFloat) {
        guard let videoView = videoView else { return }
        guard let backdropVideoView = backdropVideoView else { return }

        displayLinkAnimator?.invalidate()

        let startPosition = CGPoint(x: start.width / 2.0, y: start.height / 2.0)
        let startSize = start.size
        let startBackdropPosition = CGPoint(x: startBackdrop.midX, y: startBackdrop.midY)
        let startBackdropSize = startBackdrop.size

        let endPosition = CGPoint(x: end.width / 2.0, y: end.height / 2.0)
        let endSize = end.size
        let endBackdropPosition = CGPoint(x: endBackdrop.midX, y: endBackdrop.midY)
        let endBackdropSize = endBackdrop.size

        displayLinkAnimator = DisplayLinkAnimator(duration: duration, from: 0.0, to: 1.0, update: { progress in
            backdropVideoView.layer.position = CGPoint(
                x: startBackdropPosition.x + (endBackdropPosition.x - startBackdropPosition.x) * progress,
                y: startBackdropPosition.y + (endBackdropPosition.y - startBackdropPosition.y) * progress
            )
            backdropVideoView.layer.bounds = CGRect(origin: .zero, size: CGSize(
                width: startBackdropSize.width + (endBackdropSize.width - startBackdropSize.width) * progress,
                height: startBackdropSize.height + (endBackdropSize.height - startBackdropSize.height) * progress
            ))
            videoView.layer.position = CGPoint(
                x: startPosition.x + (endPosition.x - startPosition.x) * progress,
                y: startPosition.y + (endPosition.y - startPosition.y) * progress
            )
            videoView.layer.bounds = CGRect(origin: .zero, size: CGSize(
                width: startSize.width + (endSize.width - startSize.width) * progress,
                height: startSize.height + (endSize.height - startSize.height) * progress
            ))
        }, completion: { [weak self] in
            self?.displayLinkAnimator?.invalidate()
            self?.displayLinkAnimator = nil
        })
    }

    private func applySmoothCornersToPictureInPicture(_ cornerRadius: CGFloat) {
        let windowName = ["PG", "Hosted", "Window"].joined()
        guard let window = UIApplication.shared.windows.first(where: { type(of: $0) == NSClassFromString(windowName) }) else { return }

        window.layer.masksToBounds = true
        window.layer.cornerRadius = cornerRadius
    }

    private func updateGloss(_ value: Bool) {
        if value {
            guard self.shimmerView == nil else { return }

            let shimmerView = ShimmerEffectForegroundView()
            shimmerView.layer.cornerRadius = _cornerRadius
            self.shimmerView = shimmerView

            let borderView = UIView()
            borderView.isUserInteractionEnabled = false
            self.borderView = borderView

            let borderMaskView = UIView()
            borderMaskView.layer.borderWidth = 1.0 + UIScreenPixel
            borderMaskView.layer.borderColor = UIColor.white.cgColor
            borderMaskView.layer.cornerRadius = _cornerRadius
            borderView.mask = borderMaskView
            self.borderMaskView = borderMaskView

            let shimmerBorderView = ShimmerEffectForegroundView()
            self.shimmerBorderView = shimmerBorderView
            borderView.addSubview(shimmerBorderView)

            containerNode.view.addSubview(shimmerView)
            containerNode.view.addSubview(borderView)

            updateShimmerParameters()
        } else if self.shimmerView != nil {
            self.shimmerView?.removeFromSuperview()
            self.borderView?.removeFromSuperview()
            self.borderMaskView?.removeFromSuperview()
            self.shimmerBorderView?.removeFromSuperview()

            self.shimmerView = nil
            self.borderView = nil
            self.borderMaskView = nil
            self.shimmerBorderView = nil
        }
    }

    private func updateShimmerParameters() {
        guard let shimmerView = shimmerView else { return }
        guard let shimmerBorderView = shimmerBorderView else { return }

        let color: UIColor = .white
        let alpha: CGFloat
        let borderAlpha: CGFloat
        let compositingFilter: String?

        if color.lightness > 0.5 {
            alpha = 0.5
            borderAlpha = 0.75
            compositingFilter = "overlayBlendMode"
        } else {
            alpha = 0.2
            borderAlpha = 0.3
            compositingFilter = nil
        }

        let duration: Double = 2.0

        shimmerView.update(backgroundColor: .clear, foregroundColor: color.withAlphaComponent(alpha), gradientSize: 70.0, globalTimeOffset: false, duration: duration, horizontal: true)
        shimmerBorderView.update(backgroundColor: .clear, foregroundColor: color.withAlphaComponent(borderAlpha), gradientSize: 70.0, globalTimeOffset: false, duration: duration, horizontal: true)

        shimmerView.layer.compositingFilter = compositingFilter
        shimmerBorderView.layer.compositingFilter = compositingFilter
    }
}

extension StreamChatVideoNode: AVPictureInPictureControllerDelegate {
    // MARK: - Interface

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("pip: did start")
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if requestedExpansion {
            requestedExpansion = false

            let cornerRadius: CGFloat = (requestSmoothCornersForPictureInPicture?() ?? false) ? 12.0 : 0.0
            applySmoothCornersToPictureInPicture(cornerRadius)
        } else {
            requestClosePictureInPicture?()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("pip: did stop")
        requestedExpansion = false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        print("pip: restores")
        requestedExpansion = true
        requestBackControllerForPictureInPicture?()
        completionHandler(true)
    }
}
