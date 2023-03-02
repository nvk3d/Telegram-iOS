import Foundation
import UIKit
import DeviceProximity
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import TelegramAudio
import AccountContext
import LocalizedPeerData
import PhotoResources
import CallsEmoji
import TooltipUI
import AlertUI
import PresentationDataUtils
import DeviceAccess
import ContextUI

private func interpolateFrame(from fromValue: CGRect, to toValue: CGRect, t: CGFloat) -> CGRect {
    return CGRect(x: floorToScreenPixels(toValue.origin.x * t + fromValue.origin.x * (1.0 - t)), y: floorToScreenPixels(toValue.origin.y * t + fromValue.origin.y * (1.0 - t)), width: floorToScreenPixels(toValue.size.width * t + fromValue.size.width * (1.0 - t)), height: floorToScreenPixels(toValue.size.height * t + fromValue.size.height * (1.0 - t)))
}

private func interpolate(from: CGFloat, to: CGFloat, value: CGFloat) -> CGFloat {
    return (1.0 - value) * from + value * to
}

private final class CallVideoNode: ASDisplayNode, CallPreviewVideoNode {
    private let videoTransformContainer: ASDisplayNode
    private let videoView: PresentationCallVideoView
    
    private var effectView: UIVisualEffectView?
    private let videoPausedNode: ImmediateTextNode
    
    private var isBlurred: Bool = false
    private var currentCornerRadius: CGFloat = 0.0
    
    private let isReadyUpdated: () -> Void
    private(set) var isReady: Bool = false
    private var isReadyTimer: SwiftSignalKit.Timer?
    
    private let readyPromise = ValuePromise(false)
    var ready: Signal<Bool, NoError> {
        return self.readyPromise.get()
    }
    
    private let isFlippedUpdated: (CallVideoNode) -> Void
    
    private(set) var currentOrientation: PresentationCallVideoView.Orientation
    private(set) var currentAspect: CGFloat = 0.0
    
    private var previousVideoHeight: CGFloat?
    
    init(videoView: PresentationCallVideoView, disabledText: String?, assumeReadyAfterTimeout: Bool, isReadyUpdated: @escaping () -> Void, orientationUpdated: @escaping () -> Void, isFlippedUpdated: @escaping (CallVideoNode) -> Void) {
        self.isReadyUpdated = isReadyUpdated
        self.isFlippedUpdated = isFlippedUpdated
        
        self.videoTransformContainer = ASDisplayNode()
        self.videoView = videoView
        videoView.view.clipsToBounds = true
        videoView.view.backgroundColor = .black
        
        self.currentOrientation = videoView.getOrientation()
        self.currentAspect = videoView.getAspect()
        
        self.videoPausedNode = ImmediateTextNode()
        self.videoPausedNode.alpha = 0.0
        self.videoPausedNode.maximumNumberOfLines = 3
        
        super.init()
        
        self.backgroundColor = .black
        self.clipsToBounds = true
        
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
        
        self.videoTransformContainer.view.addSubview(self.videoView.view)
        self.addSubnode(self.videoTransformContainer)
        
        if let disabledText = disabledText {
            self.videoPausedNode.attributedText = NSAttributedString(string: disabledText, font: Font.regular(17.0), textColor: .white)
            self.addSubnode(self.videoPausedNode)
        }
        
        self.videoView.setOnFirstFrameReceived { [weak self] aspectRatio in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                if !strongSelf.isReady {
                    strongSelf.isReady = true
                    strongSelf.readyPromise.set(true)
                    strongSelf.isReadyTimer?.invalidate()
                    strongSelf.isReadyUpdated()
                }
            }
        }
        
        self.videoView.setOnOrientationUpdated { [weak self] orientation, aspect in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                if strongSelf.currentOrientation != orientation || strongSelf.currentAspect != aspect {
                    strongSelf.currentOrientation = orientation
                    strongSelf.currentAspect = aspect
                    orientationUpdated()
                }
            }
        }
        
        self.videoView.setOnIsMirroredUpdated { [weak self] _ in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.isFlippedUpdated(strongSelf)
            }
        }
        
        if assumeReadyAfterTimeout {
            self.isReadyTimer = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                if !strongSelf.isReady {
                    strongSelf.isReady = true
                    strongSelf.readyPromise.set(true)
                    strongSelf.isReadyUpdated()
                }
            }, queue: .mainQueue())
        }
        self.isReadyTimer?.start()
    }
    
    deinit {
        self.isReadyTimer?.invalidate()
    }
    
    override func didLoad() {
        super.didLoad()
        
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
    }
    
    func animateRadialMask(from fromRect: CGRect, to toRect: CGRect) {
        let maskLayer = CAShapeLayer()
        maskLayer.frame = fromRect
        
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: CGPoint(), size: fromRect.size))
        maskLayer.path = path
        
        self.layer.mask = maskLayer
        
        let topLeft = CGPoint(x: 0.0, y: 0.0)
        let topRight = CGPoint(x: self.bounds.width, y: 0.0)
        let bottomLeft = CGPoint(x: 0.0, y: self.bounds.height)
        let bottomRight = CGPoint(x: self.bounds.width, y: self.bounds.height)
        
        func distance(_ v1: CGPoint, _ v2: CGPoint) -> CGFloat {
            let dx = v1.x - v2.x
            let dy = v1.y - v2.y
            return sqrt(dx * dx + dy * dy)
        }
        
        var maxRadius = distance(toRect.center, topLeft)
        maxRadius = max(maxRadius, distance(toRect.center, topRight))
        maxRadius = max(maxRadius, distance(toRect.center, bottomLeft))
        maxRadius = max(maxRadius, distance(toRect.center, bottomRight))
        maxRadius = ceil(maxRadius)
        
        let targetFrame = CGRect(origin: CGPoint(x: toRect.center.x - maxRadius, y: toRect.center.y - maxRadius), size: CGSize(width: maxRadius * 2.0, height: maxRadius * 2.0))
        
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
        transition.updatePosition(layer: maskLayer, position: targetFrame.center)
        transition.updateTransformScale(layer: maskLayer, scale: maxRadius * 2.0 / fromRect.width, completion: { [weak self] _ in
            self?.layer.mask = nil
        })
    }

    func animateRoundedRect(from fromRect: CGRect, fromCornerRadius: CGFloat, to toRect: CGRect, toCornerRadius: CGFloat, completion: (() -> Void)? = nil) {
        let maskLayer = CAShapeLayer()
        maskLayer.frame = bounds

        let path = CGMutablePath()
        path.addRoundedRect(in: fromRect, cornerWidth: fromCornerRadius, cornerHeight: fromCornerRadius)
        maskLayer.path = path

        self.layer.mask = maskLayer

        let toPath = CGMutablePath()
        toPath.addRoundedRect(in: toRect, cornerWidth: toCornerRadius, cornerHeight: toCornerRadius)

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
        transition.updatePath(layer: maskLayer, path: toPath) { [weak self] _ in
            self?.layer.mask = nil
            completion?()
        }
    }
    
    func updateLayout(size: CGSize, cornerRadius: CGFloat, isOutgoing: Bool, deviceOrientation: UIDeviceOrientation, isCompactLayout: Bool, transition: ContainedViewLayoutTransition) {
        self.currentCornerRadius = cornerRadius
        
        var rotationAngle: CGFloat
        if false && isOutgoing && isCompactLayout {
            rotationAngle = CGFloat.pi / 2.0
        } else {
            switch self.currentOrientation {
            case .rotation0:
                rotationAngle = 0.0
            case .rotation90:
                rotationAngle = CGFloat.pi / 2.0
            case .rotation180:
                rotationAngle = CGFloat.pi
            case .rotation270:
                rotationAngle = -CGFloat.pi / 2.0
            }
            
            var additionalAngle: CGFloat = 0.0
            switch deviceOrientation {
            case .portrait:
                additionalAngle = 0.0
            case .landscapeLeft:
                additionalAngle = CGFloat.pi / 2.0
            case .landscapeRight:
                additionalAngle = -CGFloat.pi / 2.0
            case .portraitUpsideDown:
                rotationAngle = CGFloat.pi
            default:
                additionalAngle = 0.0
            }
            rotationAngle += additionalAngle
            if abs(rotationAngle - CGFloat.pi * 3.0 / 2.0) < 0.01 {
                rotationAngle = -CGFloat.pi / 2.0
            }
            if abs(rotationAngle - (-CGFloat.pi)) < 0.01 {
                rotationAngle = -CGFloat.pi + 0.001
            }
        }
        
        let rotateFrame = abs(rotationAngle.remainder(dividingBy: CGFloat.pi)) > 1.0
        let fittingSize: CGSize
        if rotateFrame {
            fittingSize = CGSize(width: size.height, height: size.width)
        } else {
            fittingSize = size
        }
        
        let unboundVideoSize = CGSize(width: self.currentAspect * 10000.0, height: 10000.0)
        
        var fittedVideoSize = unboundVideoSize.fitted(fittingSize)
        if fittedVideoSize.width < fittingSize.width || fittedVideoSize.height < fittingSize.height {
            let isVideoPortrait = unboundVideoSize.width < unboundVideoSize.height
            let isFittingSizePortrait = fittingSize.width < fittingSize.height
            
            if isCompactLayout && isVideoPortrait == isFittingSizePortrait {
                fittedVideoSize = unboundVideoSize.aspectFilled(fittingSize)
            } else {
                let maxFittingEdgeDistance: CGFloat
                if isCompactLayout {
                    maxFittingEdgeDistance = 200.0
                } else {
                    maxFittingEdgeDistance = 400.0
                }
                if fittedVideoSize.width > fittingSize.width - maxFittingEdgeDistance && fittedVideoSize.height > fittingSize.height - maxFittingEdgeDistance {
                    fittedVideoSize = unboundVideoSize.aspectFilled(fittingSize)
                }
            }
        }
        
        let rotatedVideoHeight: CGFloat = max(fittedVideoSize.height, fittedVideoSize.width)
        
        let videoFrame: CGRect = CGRect(origin: CGPoint(), size: fittedVideoSize)
        
        let videoPausedSize = self.videoPausedNode.updateLayout(CGSize(width: size.width - 16.0, height: 100.0))
        transition.updateFrame(node: self.videoPausedNode, frame: CGRect(origin: CGPoint(x: floor((size.width - videoPausedSize.width) / 2.0), y: floor((size.height - videoPausedSize.height) / 2.0)), size: videoPausedSize))
        
        self.videoTransformContainer.bounds = CGRect(origin: CGPoint(), size: videoFrame.size)
        if transition.isAnimated && !videoFrame.height.isZero, let previousVideoHeight = self.previousVideoHeight, !previousVideoHeight.isZero {
            let scaleDifference = previousVideoHeight / rotatedVideoHeight
            if abs(scaleDifference - 1.0) > 0.001 {
                transition.animateTransformScale(node: self.videoTransformContainer, from: scaleDifference, additive: true)
            }
        }
        self.previousVideoHeight = rotatedVideoHeight
        transition.updatePosition(node: self.videoTransformContainer, position: CGPoint(x: size.width / 2.0, y: size.height / 2.0))
        transition.updateTransformRotation(view: self.videoTransformContainer.view, angle: rotationAngle)
        
        let localVideoFrame = CGRect(origin: CGPoint(), size: videoFrame.size)
        self.videoView.view.bounds = localVideoFrame
        self.videoView.view.center = localVideoFrame.center
        // TODO: properly fix the issue
        // On iOS 13 and later metal layer transformation is broken if the layer does not require compositing
        self.videoView.view.alpha = 0.995
        
        if let effectView = self.effectView {
            transition.updateFrame(view: effectView, frame: localVideoFrame)
        }
        
        transition.updateCornerRadius(layer: self.layer, cornerRadius: self.currentCornerRadius)
    }
    
    func updateIsBlurred(isBlurred: Bool, light: Bool = false, animated: Bool = true) {
        if self.hasScheduledUnblur {
            self.hasScheduledUnblur = false
        }
        if self.isBlurred == isBlurred {
            return
        }
        self.isBlurred = isBlurred
        
        if isBlurred {
            if self.effectView == nil {
                let effectView = UIVisualEffectView()
                self.effectView = effectView
                effectView.frame = self.videoTransformContainer.bounds
                self.videoTransformContainer.view.addSubview(effectView)
            }
            if animated {
                UIView.animate(withDuration: 0.3, animations: {
                    self.videoPausedNode.alpha = 1.0
                    self.effectView?.effect = UIBlurEffect(style: light ? .light : .dark)
                })
            } else {
                self.effectView?.effect = UIBlurEffect(style: light ? .light : .dark)
            }
        } else if let effectView = self.effectView {
            self.effectView = nil
            UIView.animate(withDuration: 0.3, animations: {
                self.videoPausedNode.alpha = 0.0
                effectView.effect = nil
            }, completion: { [weak effectView] _ in
                effectView?.removeFromSuperview()
            })
        }
    }
    
    private var hasScheduledUnblur = false
    func flip(withBackground: Bool) {
        if withBackground {
            self.backgroundColor = .black
        }
        UIView.transition(with: withBackground ? self.videoTransformContainer.view : self.view, duration: 0.4, options: [.transitionFlipFromLeft, .curveEaseOut], animations: {
            UIView.performWithoutAnimation {
                self.updateIsBlurred(isBlurred: true, light: false, animated: false)
            }
        }) { finished in
            self.backgroundColor = nil
            self.hasScheduledUnblur = true
            Queue.mainQueue().after(0.5) {
                if self.hasScheduledUnblur {
                    self.updateIsBlurred(isBlurred: false)
                }
            }
        }
    }
}

final class CallControllerNode: ViewControllerTracingNode, CallControllerNodeProtocol {
    private enum AudioImageState {
        case pulse
        case active
        case ended
    }

    private enum VideoNodeCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
    
    private let sharedContext: SharedAccountContext
    private let account: Account
    
    private let statusBar: StatusBar
    
    private var presentationData: PresentationData
    private var peer: Peer?
    private let debugInfo: Signal<(String, String), NoError>
    private var forceReportRating = false
    private let easyDebugAccess: Bool
    private let call: PresentationCall
    
    private let containerTransformationNode: ASDisplayNode
    private let containerNode: ASDisplayNode
    private let videoContainerNode: PinchSourceContainerNode

    private let backgroundNode: CallControllerBackgroundNode
    private let audioNode: CallControllerAudioNode
    private let imageNode: TransformImageNode
    private let statusNode: CallControllerStatusNode
    
    private var candidateIncomingVideoNodeValue: CallVideoNode?
    private var incomingVideoNodeValue: CallVideoNode?
    private var incomingVideoViewRequested: Bool = false
    private var candidateOutgoingVideoNodeValue: CallVideoNode?
    private var outgoingVideoNodeValue: CallVideoNode?
    private var outgoingVideoViewRequested: Bool = false
    
    private var removedMinimizedVideoNodeValue: CallVideoNode?
    private var removedExpandedVideoNodeValue: CallVideoNode?
    
    private var isRequestingVideo: Bool = false
    private var animateRequestedVideoOnce: Bool = false
    
    private var hiddenUIForActiveVideoCallOnce: Bool = false
    private var hideUIForActiveVideoCallTimer: SwiftSignalKit.Timer?

    private var animationsPauseTimer: SwiftSignalKit.Timer?
    
    private var displayedCameraConfirmation: Bool = false
    private var displayedCameraTooltip: Bool = false

    private var audioImageState: AudioImageState = .ended
        
    private var expandedVideoNode: CallVideoNode?
    private var minimizedVideoNode: CallVideoNode?
    private var disableAnimationForExpandedVideoOnce: Bool = false
    private var animationSnapshotExpandedView: UIView? = nil
    private var animationSnapshotMinimizedView: UIView? = nil
    
    private var outgoingVideoNodeCorner: VideoNodeCorner = .bottomRight
    private let backButtonArrowNode: ASImageNode
    private let backButtonNode: HighlightableButtonNode
    private let toastNode: CallControllerToastContainerNode
    private let statusToastNode: CallControllerCustomToastNode
    private let buttonsNode: CallControllerButtonsNode
    private var keyPreviewNode: CallControllerKeyPreviewNode?

    private let ratingNode: CallControllerRatingNode
    private let closeContainerNode: CallControllerCloseContainerNode
    
    private var debugNode: CallDebugNode?
    
    private var keyTextData: (Data, String)?
    private let keyButtonNode: CallControllerKeyButton
    
    private var validLayout: (ContainerViewLayout, CGFloat)?
    private var disableActionsUntilTimestamp: Double = 0.0

    private var displayingStatusToast: Bool = false

    private var displayedActiveStateOnce: Bool = false
    private var displayedVersionOutdatedAlert: Bool = false

    private var animationSnapshotExist: Bool {
        animationSnapshotMinimizedView != nil || animationSnapshotExpandedView != nil
    }
    
    var isMuted: Bool = false {
        didSet {
            self.buttonsNode.isMuted = self.isMuted
            self.updateToastContent()
            if let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        }
    }
    
    private var shouldStayHiddenUntilConnection: Bool = false
    
    private var audioOutputState: ([AudioSessionOutput], currentOutput: AudioSessionOutput?)?
    private var callState: PresentationCallState?
    
    var toggleMute: (() -> Void)?
    var setCurrentAudioOutput: ((AudioSessionOutput) -> Void)?
    var beginAudioOuputSelection: ((Bool) -> Void)?
    var acceptCall: (() -> Void)?
    var endCall: (() -> Void)?
    var back: (() -> Void)?
    var presentCallRating: ((CallId, Bool) -> Void)?
    var callEnded: ((Bool) -> Void)?
    var callRated: ((Bool, Bool) -> Void)?
    var dismissedInteractively: (() -> Void)?
    var present: ((ViewController) -> Void)?
    var dismissAllTooltips: (() -> Void)?
    
    private var toastContent: CallControllerToastContent?
    private var displayToastsAfterTimestamp: Double?
    
    private var buttonsMode: CallControllerButtonsMode?
    
    private var isUIHidden: Bool = false
    private var isVideoPaused: Bool = false
    private var isVideoPinched: Bool = false
    private var isAnimationsPaused: Bool = false

    private var rateCallId: CallId?
    
    private enum PictureInPictureGestureState {
        case none
        case collapsing(didSelectCorner: Bool)
        case dragging(initialPosition: CGPoint, draggingPosition: CGPoint)
    }

    private var proximityListener: Int?
    
    private var pictureInPictureGestureState: PictureInPictureGestureState = .none
    private var pictureInPictureCorner: VideoNodeCorner = .topRight
    private var pictureInPictureTransitionFraction: CGFloat = 0.0
    
    private var deviceOrientation: UIDeviceOrientation = .portrait
    private var orientationDidChangeObserver: NSObjectProtocol?
    
    private var currentRequestedAspect: CGFloat?
    
    init(sharedContext: SharedAccountContext, account: Account, presentationData: PresentationData, statusBar: StatusBar, debugInfo: Signal<(String, String), NoError>, shouldStayHiddenUntilConnection: Bool = false, easyDebugAccess: Bool, call: PresentationCall) {
        self.sharedContext = sharedContext
        self.account = account
        self.presentationData = presentationData
        self.statusBar = statusBar
        self.debugInfo = debugInfo
        self.shouldStayHiddenUntilConnection = shouldStayHiddenUntilConnection
        self.easyDebugAccess = easyDebugAccess
        self.call = call
        
        self.containerTransformationNode = ASDisplayNode()
        self.containerTransformationNode.clipsToBounds = true
        
        self.containerNode = ASDisplayNode()
        
        self.videoContainerNode = PinchSourceContainerNode()

        self.backgroundNode = CallControllerBackgroundNode()

        self.audioNode = CallControllerAudioNode()

        self.imageNode = TransformImageNode()
        self.imageNode.contentAnimations = [.subsequentUpdates]
        self.imageNode.clipsToBounds = true

        self.statusNode = CallControllerStatusNode()
        
        self.backButtonArrowNode = ASImageNode()
        self.backButtonArrowNode.displayWithoutProcessing = true
        self.backButtonArrowNode.displaysAsynchronously = false
        self.backButtonArrowNode.image = NavigationBarTheme.generateBackArrowImage(color: .white)
        self.backButtonArrowNode.alpha = 0.0
        self.backButtonNode = HighlightableButtonNode()
        self.backButtonNode.alpha = 0.0
        
        self.buttonsNode = CallControllerButtonsNode(strings: self.presentationData.strings)
        self.toastNode = CallControllerToastContainerNode(strings: self.presentationData.strings)
        self.statusToastNode = CallControllerCustomToastNode()
        self.keyButtonNode = CallControllerKeyButton()
        self.keyButtonNode.accessibilityElementsHidden = false

        self.ratingNode = CallControllerRatingNode()
        self.ratingNode.alpha = 0.0
        self.closeContainerNode = CallControllerCloseContainerNode()
        self.closeContainerNode.alpha = 0.0
        
        super.init()
        
        self.containerNode.backgroundColor = .black
        
        self.addSubnode(self.containerTransformationNode)
        self.containerTransformationNode.addSubnode(self.containerNode)
        
        self.backButtonNode.setTitle(presentationData.strings.Common_Back, with: Font.regular(17.0), with: .white, for: [])
        self.backButtonNode.accessibilityLabel = presentationData.strings.Call_VoiceOver_Minimize
        self.backButtonNode.accessibilityTraits = [.button]
        self.backButtonNode.hitTestSlop = UIEdgeInsets(top: -8.0, left: -20.0, bottom: -8.0, right: -8.0)
        self.backButtonNode.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.backButtonNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backButtonArrowNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backButtonNode.alpha = 0.4
                    strongSelf.backButtonArrowNode.alpha = 0.4
                } else {
                    strongSelf.backButtonNode.alpha = 1.0
                    strongSelf.backButtonArrowNode.alpha = 1.0
                    strongSelf.backButtonNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                    strongSelf.backButtonArrowNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                }
            }
        }

        self.statusToastNode.update(title: "Weak network signal")
        self.statusToastNode.alpha = 0.0

        self.containerNode.addSubnode(self.backgroundNode)
        self.containerNode.addSubnode(self.audioNode)
        self.containerNode.addSubnode(self.imageNode)
        self.containerNode.addSubnode(self.videoContainerNode)
        self.containerNode.addSubnode(self.statusNode)
        self.containerNode.addSubnode(self.buttonsNode)
        self.containerNode.addSubnode(self.ratingNode)
        self.containerNode.addSubnode(self.closeContainerNode)
        self.containerNode.addSubnode(self.toastNode)
        self.containerNode.addSubnode(self.statusToastNode)
        self.containerNode.addSubnode(self.keyButtonNode)
        self.containerNode.addSubnode(self.backButtonArrowNode)
        self.containerNode.addSubnode(self.backButtonNode)

        self.audioNode.setSignal(call.audioLevel)
        
        self.buttonsNode.mute = { [weak self] in
            self?.toggleMute?()
            self?.cancelScheduledUIHiding()
        }
        
        self.buttonsNode.speaker = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.beginAudioOuputSelection?(strongSelf.hasVideoNodes)
            strongSelf.cancelScheduledUIHiding()
        }
                
        self.buttonsNode.acceptOrEnd = { [weak self] in
            guard let strongSelf = self, let callState = strongSelf.callState else {
                return
            }
            switch callState.state {
            case .active, .connecting, .reconnecting:
                strongSelf.endCall?()
                strongSelf.cancelScheduledUIHiding()
            case .requesting:
                strongSelf.endCall?()
            case .ringing:
                strongSelf.acceptCall?()
            default:
                break
            }
        }
        
        self.buttonsNode.decline = { [weak self] in
            self?.endCall?()
        }
        
        self.buttonsNode.toggleVideo = { [weak self] in
            guard let strongSelf = self, let callState = strongSelf.callState else {
                return
            }
            switch callState.state {
            case .active:
                var isScreencastActive = false
                switch callState.videoState {
                case .active(true), .paused(true):
                    isScreencastActive = true
                default:
                    break
                }

                if isScreencastActive {
                    (strongSelf.call as! PresentationCallImpl).disableScreencast()
                } else if strongSelf.outgoingVideoNodeValue == nil {
                    DeviceAccess.authorizeAccess(to: .camera(.videoCall), onlyCheck: true, presentationData: strongSelf.presentationData, present: { [weak self] c, a in
                        if let strongSelf = self {
                            strongSelf.present?(c)
                        }
                    }, openSettings: { [weak self] in
                        self?.sharedContext.applicationBindings.openSettings()
                    }, _: { [weak self] ready in
                        guard let strongSelf = self, ready else {
                            return
                        }
                        let proceed = {
                            strongSelf.displayedCameraConfirmation = true
                            switch callState.videoState {
                            case .inactive:
                                strongSelf.isRequestingVideo = true
                                strongSelf.updateButtonsMode()
                            default:
                                break
                            }
                            strongSelf.call.requestVideo()
                        }

                        if let call = strongSelf.call as? PresentationCallImpl {
                            call.invalidateSwitchingVideoCamera()
                        }

                        strongSelf.call.makeOutgoingVideoView(completion: { [weak self] outgoingVideoView in
                            guard let strongSelf = self else {
                                return
                            }
                            
                            if let outgoingVideoView = outgoingVideoView {
                                outgoingVideoView.view.backgroundColor = .black
                                outgoingVideoView.view.clipsToBounds = true
                                
                                var updateLayoutImpl: ((ContainerViewLayout, CGFloat) -> Void)?
                                
                                let outgoingVideoNode = CallVideoNode(videoView: outgoingVideoView, disabledText: nil, assumeReadyAfterTimeout: true, isReadyUpdated: {
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                }, orientationUpdated: {
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                }, isFlippedUpdated: { _ in
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                })

                                let videoButtonConvertedFrame = strongSelf.buttonsNode.videoButtonFrame().flatMap { strongSelf.buttonsNode.view.convert($0, to: strongSelf.view) } ?? .zero
                                let fromRectSize = CGSize(width: 1.0, height: 1.0)
                                let fromRect = CGRect(
                                    x: videoButtonConvertedFrame.minX + (videoButtonConvertedFrame.width - fromRectSize.width) / 2.0,
                                    y: videoButtonConvertedFrame.minY + (videoButtonConvertedFrame.height - fromRectSize.height) / 2.0,
                                    width: fromRectSize.width,
                                    height: fromRectSize.height
                                )

                                strongSelf.isRequestingVideo = true
                                strongSelf.updateButtonsMode()

                                let controller = CallCameraPreviewController(
                                    fromRect: fromRect,
                                    sharedContext: strongSelf.sharedContext,
                                    cameraNode: outgoingVideoNode,
                                    requestEndFrame: { [weak self, weak outgoingVideoNode] in
                                        guard let self = self else { return nil }
                                        guard let layout = self.validLayout else { return nil }
                                        guard self.expandedVideoNode != nil else { return nil }

                                        return self.calculatePreviewVideoRect(layout: layout.0, navigationHeight: layout.1, temporaryMinimizedNode: outgoingVideoNode)
                                    },
                                    shareCamera: { _, _ in
                                        proceed()
                                    },
                                    switchCamera: { [weak self] in
                                        Queue.mainQueue().after(0.1) {
                                            self?.call.switchVideoCamera()
                                        }
                                    },
                                    cancel: { [weak self] in
                                        self?.isRequestingVideo = false
                                        self?.updateButtonsMode()
                                    }
                                )
                                strongSelf.present?(controller)
                                
                                updateLayoutImpl = { [weak controller] layout, navigationBarHeight in
                                    controller?.containerLayoutUpdated(layout, transition: .immediate)
                                }
                            }
                        })
                    })
                } else {
                    strongSelf.call.disableVideo()
                    strongSelf.cancelScheduledUIHiding()
                }
            default:
                break
            }
        }
        
        self.buttonsNode.rotateCamera = { [weak self] in
            guard let strongSelf = self, !strongSelf.areUserActionsDisabledNow() else {
                return
            }
            strongSelf.disableActionsUntilTimestamp = CACurrentMediaTime() + 1.0
            if let outgoingVideoNode = strongSelf.outgoingVideoNodeValue {
                outgoingVideoNode.flip(withBackground: outgoingVideoNode !== strongSelf.minimizedVideoNode)
            }
            strongSelf.call.switchVideoCamera()
            if let _ = strongSelf.outgoingVideoNodeValue {
                if let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                }
            }
            strongSelf.cancelScheduledUIHiding()
        }
        
        self.keyButtonNode.addTarget(self, action: #selector(self.keyPressed), forControlEvents: .touchUpInside)
        
        self.backButtonNode.addTarget(self, action: #selector(self.backPressed), forControlEvents: .touchUpInside)

        self.ratingNode.rateTapped = { [weak self] rate in
            guard let self = self else { return }

            if let callId = self.rateCallId {
                let _ = rateCallAndSendLogs(engine: TelegramEngine(account: account), callId: callId, starsCount: rate, comment: "", userInitiated: false, includeLogs: false).start()
            }
            self.callRated?(false, false)
        }
        self.closeContainerNode.requestAnimationEnded = { [weak self] force in
            guard let self = self else { return }
            self.callRated?(force, true)
        }
        
        if shouldStayHiddenUntilConnection {
            self.containerNode.alpha = 0.0
            Queue.mainQueue().after(3.0, { [weak self] in
                self?.containerNode.alpha = 1.0
                self?.animateIn()
            })
        } else if call.isVideo && call.isOutgoing {
            self.containerNode.alpha = 0.0
            Queue.mainQueue().after(1.0, { [weak self] in
                self?.containerNode.alpha = 1.0
                self?.animateIn()
            })
        }
        
        self.orientationDidChangeObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            let deviceOrientation = UIDevice.current.orientation
            if strongSelf.deviceOrientation != deviceOrientation {
                strongSelf.deviceOrientation = deviceOrientation
                if let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                }
            }
        })
        
        self.videoContainerNode.activate = { [weak self] sourceNode in
            guard let strongSelf = self else {
                return
            }
            let pinchController = PinchController(sourceNode: sourceNode, getContentAreaInScreenSpace: {
                return UIScreen.main.bounds
            })
            strongSelf.sharedContext.mainWindow?.presentInGlobalOverlay(pinchController)
            strongSelf.isVideoPinched = true
            
            strongSelf.videoContainerNode.contentNode.clipsToBounds = true
            strongSelf.videoContainerNode.backgroundColor = .black
            
            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                strongSelf.videoContainerNode.contentNode.cornerRadius = layout.deviceMetrics.screenCornerRadius
                
                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        }
        
        self.videoContainerNode.animatedOut = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isVideoPinched = false
            
            strongSelf.videoContainerNode.backgroundColor = .clear
            strongSelf.videoContainerNode.contentNode.cornerRadius = 0.0
            
            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        }

        proximityListener = DeviceProximityManager.shared().add { [weak self] proximited in
            guard let self = self else { return }
            guard proximited else { return }
            self.updateAnimationsState(paused: true, force: true)
        }
    }
    
    deinit {
        if let orientationDidChangeObserver = self.orientationDidChangeObserver {
            NotificationCenter.default.removeObserver(orientationDidChangeObserver)
        }
        if let proximityListener = proximityListener {
            DeviceProximityManager.shared().remove(proximityListener)
        }
        animationsPauseTimer?.invalidate()
        animationsPauseTimer = nil
    }
    
    func displayCameraTooltip() {
        guard self.pictureInPictureTransitionFraction.isZero, let location = self.buttonsNode.videoButtonFrame().flatMap({ frame -> CGRect in
            return self.buttonsNode.view.convert(frame, to: self.view)
        }) else {
            return
        }
                
        self.present?(TooltipScreen(account: self.account, text: self.presentationData.strings.Call_CameraOrScreenTooltip, style: .light, icon: nil, location: .point(location.offsetBy(dx: 0.0, dy: -14.0), .bottom), displayDuration: .custom(5.0), shouldDismissOnTouch: { _ in
            return .dismiss(consume: false)
        }))
    }
    
    override func didLoad() {
        super.didLoad()
        
        let panRecognizer = CallPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        panRecognizer.shouldBegin = { [weak self] _ in
            guard let strongSelf = self else {
                return false
            }
            if strongSelf.areUserActionsDisabledNow() {
                return false
            }
            return true
        }
        self.view.addGestureRecognizer(panRecognizer)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:)))
        self.view.addGestureRecognizer(tapRecognizer)
    }
    
    func updatePeer(accountPeer: Peer, peer: Peer, hasOther: Bool) {
        if !arePeersEqual(self.peer, peer) {
            self.peer = peer
            if let peerReference = PeerReference(peer), !peer.profileImageRepresentations.isEmpty {
                let representations: [ImageRepresentationWithReference] = peer.profileImageRepresentations.map({ ImageRepresentationWithReference(representation: $0, reference: .avatar(peer: peerReference, resource: $0.resource)) })
                self.imageNode.setSignal(chatAvatarGalleryPhoto(account: self.account, representations: representations, immediateThumbnailData: nil, autoFetchFullSize: true))
            } else {
                self.imageNode.setSignal(callDefaultBackground())
            }
            
            self.toastNode.title = EnginePeer(peer).compactDisplayTitle
            self.statusNode.title = EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)
            if hasOther {
                self.statusNode.subtitle = self.presentationData.strings.Call_AnsweringWithAccount(EnginePeer(accountPeer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                
                if let callState = self.callState {
                    self.updateCallState(callState)
                }
            }
            
            if let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        }
    }
    
    func updateAudioOutputs(availableOutputs: [AudioSessionOutput], currentOutput: AudioSessionOutput?) {
        if self.audioOutputState?.0 != availableOutputs || self.audioOutputState?.1 != currentOutput {
            self.audioOutputState = (availableOutputs, currentOutput)
            self.updateButtonsMode()
            
            self.setupAudioOutputs()
        }
    }
    
    private func setupAudioOutputs() {
        if self.outgoingVideoNodeValue != nil || self.incomingVideoNodeValue != nil || self.candidateOutgoingVideoNodeValue != nil || self.candidateIncomingVideoNodeValue != nil {
            if let audioOutputState = self.audioOutputState, let currentOutput = audioOutputState.currentOutput {
                switch currentOutput {
                case .headphones, .speaker:
                    break
                case let .port(port) where port.type == .bluetooth || port.type == .wired:
                    break
                default:
                    self.setCurrentAudioOutput?(.speaker)
                }
            }
        }
    }
    
    func updateCallState(_ callState: PresentationCallState) {
        self.callState = callState

        var statusTitle: String?
        let statusValue: CallControllerStatusValue
        var statusReception: Int32?
        
        switch callState.remoteVideoState {
        case .active, .paused:
            if !self.incomingVideoViewRequested {
                self.incomingVideoViewRequested = true
                let delayUntilInitialized = true
                self.call.makeIncomingVideoView(completion: { [weak self] incomingVideoView in
                    guard let strongSelf = self else {
                        return
                    }
                    if let incomingVideoView = incomingVideoView {
                        incomingVideoView.view.backgroundColor = .black
                        incomingVideoView.view.clipsToBounds = true
                        
                        let applyNode: () -> Void = {
                            guard let strongSelf = self, let incomingVideoNode = strongSelf.candidateIncomingVideoNodeValue else {
                                return
                            }
                            strongSelf.candidateIncomingVideoNodeValue = nil

                            if strongSelf.incomingVideoViewRequested {
                                strongSelf.animateRequestedVideoOnce = true
                            }
                            
                            strongSelf.incomingVideoNodeValue = incomingVideoNode
                            if let expandedVideoNode = strongSelf.expandedVideoNode {
                                strongSelf.minimizedVideoNode = expandedVideoNode
                                strongSelf.videoContainerNode.contentNode.insertSubnode(incomingVideoNode, belowSubnode: expandedVideoNode)
                            } else {
                                strongSelf.videoContainerNode.contentNode.addSubnode(incomingVideoNode)
                            }
                            strongSelf.expandedVideoNode = incomingVideoNode
                            strongSelf.updateButtonsMode(transition: .animated(duration: 0.4, curve: .spring))
                            
                            strongSelf.updateDimVisibility()
                            strongSelf.maybeScheduleUIHidingForActiveVideoCall()
                        }
                        
                        let incomingVideoNode = CallVideoNode(videoView: incomingVideoView, disabledText: strongSelf.presentationData.strings.Call_RemoteVideoPaused(strongSelf.peer.flatMap(EnginePeer.init)?.compactDisplayTitle ?? "").string, assumeReadyAfterTimeout: false, isReadyUpdated: {
                            if delayUntilInitialized {
                                Queue.mainQueue().after(0.1, {
                                    applyNode()
                                })
                            }
                        }, orientationUpdated: {
                            guard let strongSelf = self else {
                                return
                            }
                            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }, isFlippedUpdated: { _ in
                        })
                        strongSelf.candidateIncomingVideoNodeValue = incomingVideoNode
                        strongSelf.setupAudioOutputs()
                        
                        if !delayUntilInitialized {
                            applyNode()
                        }
                    }
                })
            }
        case .inactive:
            self.candidateIncomingVideoNodeValue = nil
            if let incomingVideoNodeValue = self.incomingVideoNodeValue {
                if self.minimizedVideoNode == incomingVideoNodeValue {
                    self.minimizedVideoNode = nil
                    self.removedMinimizedVideoNodeValue = incomingVideoNodeValue
                }
                if self.expandedVideoNode == incomingVideoNodeValue {
                    self.expandedVideoNode = nil
                    self.removedExpandedVideoNodeValue = incomingVideoNodeValue
                    
                    if let minimizedVideoNode = self.minimizedVideoNode {
                        self.expandedVideoNode = minimizedVideoNode
                        self.minimizedVideoNode = nil
                    }
                }
                self.incomingVideoNodeValue = nil
                self.incomingVideoViewRequested = false
            }
        }
        
        switch callState.videoState {
        case .active(false), .paused(false):
            if !self.outgoingVideoViewRequested {
                self.outgoingVideoViewRequested = true
                let delayUntilInitialized = self.isRequestingVideo
                self.call.makeOutgoingVideoView(completion: { [weak self] outgoingVideoView in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    if let outgoingVideoView = outgoingVideoView {
                        outgoingVideoView.view.backgroundColor = .black
                        outgoingVideoView.view.clipsToBounds = true
                        
                        let applyNode: () -> Void = {
                            guard let strongSelf = self, let outgoingVideoNode = strongSelf.candidateOutgoingVideoNodeValue else {
                                return
                            }
                            strongSelf.candidateOutgoingVideoNodeValue = nil
                            
                            if strongSelf.isRequestingVideo {
                                strongSelf.isRequestingVideo = false
                                strongSelf.animateRequestedVideoOnce = true
                            }
                            
                            strongSelf.outgoingVideoNodeValue = outgoingVideoNode
                            if let expandedVideoNode = strongSelf.expandedVideoNode {
                                strongSelf.minimizedVideoNode = outgoingVideoNode
                                strongSelf.videoContainerNode.contentNode.insertSubnode(outgoingVideoNode, aboveSubnode: expandedVideoNode)
                            } else {
                                strongSelf.expandedVideoNode = outgoingVideoNode
                                strongSelf.videoContainerNode.contentNode.addSubnode(outgoingVideoNode)
                            }
                            strongSelf.updateButtonsMode(transition: .animated(duration: 0.4, curve: .spring))
                            
                            strongSelf.updateDimVisibility()
                            strongSelf.maybeScheduleUIHidingForActiveVideoCall()
                        }
                        
                        let outgoingVideoNode = CallVideoNode(videoView: outgoingVideoView, disabledText: nil, assumeReadyAfterTimeout: true, isReadyUpdated: {
                            if delayUntilInitialized {
                                Queue.mainQueue().after(0.4, {
                                    applyNode()
                                })
                            }
                        }, orientationUpdated: {
                            guard let strongSelf = self else {
                                return
                            }
                            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }, isFlippedUpdated: { videoNode in
                            guard let _ = self else {
                                return
                            }
                            /*if videoNode === strongSelf.minimizedVideoNode, let tempView = videoNode.view.snapshotView(afterScreenUpdates: true) {
                                videoNode.view.superview?.insertSubview(tempView, aboveSubview: videoNode.view)
                                videoNode.view.frame = videoNode.frame
                                let transitionOptions: UIView.AnimationOptions = [.transitionFlipFromRight, .showHideTransitionViews]

                                UIView.transition(with: tempView, duration: 1.0, options: transitionOptions, animations: {
                                    tempView.isHidden = true
                                }, completion: { [weak tempView] _ in
                                    tempView?.removeFromSuperview()
                                })

                                videoNode.view.isHidden = true
                                UIView.transition(with: videoNode.view, duration: 1.0, options: transitionOptions, animations: {
                                    videoNode.view.isHidden = false
                                })
                            }*/
                        })
                        
                        strongSelf.candidateOutgoingVideoNodeValue = outgoingVideoNode
                        strongSelf.setupAudioOutputs()
                        
                        if !delayUntilInitialized {
                            applyNode()
                        }
                    }
                })
            }
        default:
            self.candidateOutgoingVideoNodeValue = nil
            if let outgoingVideoNodeValue = self.outgoingVideoNodeValue {
                if self.minimizedVideoNode == outgoingVideoNodeValue {
                    self.minimizedVideoNode = nil
                    self.removedMinimizedVideoNodeValue = outgoingVideoNodeValue
                }
                if self.expandedVideoNode == self.outgoingVideoNodeValue {
                    self.expandedVideoNode = nil
                    self.removedExpandedVideoNodeValue = outgoingVideoNodeValue
                    
                    if let minimizedVideoNode = self.minimizedVideoNode {
                        self.expandedVideoNode = minimizedVideoNode
                        self.minimizedVideoNode = nil
                    }
                }
                self.outgoingVideoNodeValue = nil
                self.outgoingVideoViewRequested = false
            }
        }
        
        if let incomingVideoNode = self.incomingVideoNodeValue {
            switch callState.state {
            case .terminating, .terminated:
                break
            default:
                let isActive: Bool
                switch callState.remoteVideoState {
                case .inactive, .paused:
                    isActive = false
                case .active:
                    isActive = true
                }
                incomingVideoNode.updateIsBlurred(isBlurred: !isActive)
            }
        }

        let generateDeclineButtonImage: () -> UIImage? = { generateTintedImage(image: UIImage(bundleImageName: "Call/CallDeclineButtonSmall"), color: .white) }
                
        switch callState.state {
        case .waiting, .connecting:
            statusValue = .text(string: self.presentationData.strings.Call_StatusConnecting, loading: true)
        case let .requesting(ringing):
            if ringing {
                statusValue = .text(string: self.presentationData.strings.Call_StatusRinging, loading: true)
            } else {
                statusValue = .text(string: self.presentationData.strings.Call_StatusRequesting, loading: true)
            }
        case .terminating:
            statusTitle = self.presentationData.strings.Call_StatusEnded
            statusValue = .timestamp(icon: generateDeclineButtonImage())
        case let .terminated(_, reason, _):
            if let reason = reason {
                switch reason {
                case let .ended(type):
                    switch type {
                    case .busy:
                        statusTitle = self.presentationData.strings.Call_StatusBusy
                        statusValue = .timestamp(icon: generateDeclineButtonImage())
                    case .hungUp, .missed:
                        statusTitle = self.presentationData.strings.Call_StatusEnded
                        statusValue = .timestamp(icon: generateDeclineButtonImage())
                    }
                case let .error(error):
                    let text = self.presentationData.strings.Call_StatusFailed
                    switch error {
                    case let .notSupportedByPeer(isVideo):
                        if !self.displayedVersionOutdatedAlert, let peer = self.peer {
                            self.displayedVersionOutdatedAlert = true

                            let text: String
                            if isVideo {
                                text = self.presentationData.strings.Call_ParticipantVideoVersionOutdatedError(EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                            } else {
                                text = self.presentationData.strings.Call_ParticipantVersionOutdatedError(EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                            }

                            self.present?(textAlertController(sharedContext: self.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {
                            })]))
                        }
                    default:
                        break
                    }
                    statusTitle = text
                    statusValue = .timestamp(icon: generateDeclineButtonImage())
                }
            } else {
                statusTitle = self.presentationData.strings.Call_StatusEnded
                statusValue = .timestamp(icon: generateDeclineButtonImage())
            }
        case .ringing:
            var text: String
            if self.call.isVideo {
                text = self.presentationData.strings.Call_IncomingVideoCall
            } else {
                text = self.presentationData.strings.Call_IncomingVoiceCall
            }
            if !self.statusNode.subtitle.isEmpty {
                text += "\n\(self.statusNode.subtitle)"
            }
            statusValue = .text(string: text, loading: true)
        case .active(let timestamp, let reception, let keyVisualHash), .reconnecting(let timestamp, let reception, let keyVisualHash):
            let strings = self.presentationData.strings

            if self.keyTextData?.0 != keyVisualHash {
                let text = stringForEmojiHashOfData(keyVisualHash, 4)!
                self.keyTextData = (keyVisualHash, text)

                self.keyButtonNode.key = text

                let keyTextSize = self.keyButtonNode.measure(CGSize(width: 200.0, height: 200.0))
                self.keyButtonNode.frame = CGRect(origin: self.keyButtonNode.frame.origin, size: keyTextSize)

                self.keyButtonNode.animateIn()

                if let (layout, navigationBarHeight) = self.validLayout {
                    self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                }
            }

            if case .active = callState.state {
                statusValue = .timer({ value, _ in value }, timestamp)
                statusReception = reception
            } else {
                statusValue = .text(string: strings.Call_StatusConnecting, loading: true)
            }
        }
        if self.shouldStayHiddenUntilConnection {
            switch callState.state {
                case .connecting, .active:
                    self.containerNode.alpha = 1.0
                default:
                    break
            }
        }

        if !hasVideoNodes {
            if removedExpandedVideoNodeValue != nil || removedMinimizedVideoNodeValue != nil {
                updateAnimationsState(paused: false, force: false)
            } else if case .active = callState.state {
                if !isAnimationsPaused, animationsPauseTimer == nil {
                    updateAnimationsState(paused: true, force: false)
                }
            } else {
                updateAnimationsState(paused: false, force: true)
            }
        } else if !isAnimationsPaused {
            updateAnimationsState(paused: true, force: true)
        }

        if let statusTitle = statusTitle {
            self.statusNode.title = statusTitle
        }
        self.statusNode.status = statusValue
        self.statusNode.reception = statusReception
        
        if let callState = self.callState {
            switch callState.state {
            case .active, .connecting, .reconnecting:
                break
            default:
                self.isUIHidden = false
            }
        }

        self.updateToastContent()
        self.updateButtonsMode()
        self.updateDimVisibility()
        self.updateAudioImageState()
        self.updateAudioWaves()
        self.updateBackgroundState()
        self.updateStatusToast()
        
        if self.incomingVideoViewRequested || self.outgoingVideoViewRequested {
            if self.incomingVideoViewRequested && self.outgoingVideoViewRequested {
                self.displayedCameraTooltip = true
            }
            self.displayedCameraConfirmation = true
        }
        if self.incomingVideoViewRequested && !self.outgoingVideoViewRequested && !self.displayedCameraTooltip && (self.toastContent?.isEmpty ?? true) {
            self.displayedCameraTooltip = true
            Queue.mainQueue().after(2.0) {
                self.displayCameraTooltip()
            }
        }
        
        if case let .terminated(id, _, reportRating) = callState.state, let callId = id {
            let presentRating = reportRating || self.forceReportRating
            if presentRating, rateCallId == nil {
                //self.presentCallRating?(callId, self.call.isVideo)
                self.rateCallId = callId
                let transition: ContainedViewLayoutTransition = .animated(duration: 0.5, curve: .spring)
                transition.updateAlpha(node: self.ratingNode, alpha: 1.0)

                let animation = ratingNode.layer.springAnimation(from: 0.85 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.5)
                self.ratingNode.layer.add(animation, forKey: "transform.scale")

                self.closeContainerNode.alpha = 1.0
                self.closeContainerNode.animateIn(buttonsNode.endButtonPosition())
            }
            self.callEnded?(presentRating)
        }
        
        let hasIncomingVideoNode = self.incomingVideoNodeValue != nil && self.expandedVideoNode === self.incomingVideoNodeValue
        self.videoContainerNode.isPinchGestureEnabled = hasIncomingVideoNode
    }

    private func updateAudioImageState() {
        guard let callState = self.callState else { return }

        let nextState: AudioImageState
        switch callState.state {
        case .active:
            nextState = .active
        case .waiting, .ringing, .connecting, .reconnecting, .requesting:
            nextState = .pulse
        case .terminating, .terminated:
            nextState = .ended
        }

        let force: Bool = nextState == .pulse && imageNode.layer.animation(forKey: "transform.scale") == nil

        guard nextState != audioImageState || force else { return }
        audioImageState = nextState

        let nodes: [ASDisplayNode] = [audioNode, imageNode]

        switch audioImageState {
        case .pulse:
            for i in 0 ..< nodes.count {
                let node = nodes[i]
                let presentation = node.layer.presentation() ?? node.layer

                let t = presentation.transform
                let currentScale = sqrt((t.m11 * t.m11) + (t.m12 * t.m12) + (t.m13 * t.m13))

                if node.layer.animation(forKey: "transform.scale") != nil {
                    node.layer.removeAnimation(forKey: "transform.scale")
                }

                var values: [Float] = i == 0
                    ? [Float(currentScale), 1.0, 1.2, 1.0, 0.95]
                    : [Float(currentScale), 1.0, 1.05, 1.0, 0.95]

                if currentScale == 1.0 {
                    _ = values.removeFirst()
                }

                let anim = CAKeyframeAnimation(keyPath: "transform.scale")
                anim.values = values
                anim.duration = 1.5
                anim.autoreverses = true
                anim.repeatCount = .infinity

                node.layer.add(anim, forKey: "transform.scale")
            }

        case .active:
            for i in 0 ..< nodes.count {
                let node = nodes[i]
                let presentation = node.layer.presentation() ?? node.layer

                let t = presentation.transform
                let currentScale = sqrt((t.m11 * t.m11) + (t.m12 * t.m12) + (t.m13 * t.m13))
                let maxScale: CGFloat = i == 0 ? 1.4 : 1.15
                let minScale: CGFloat = i == 0 ? 0.85 : 0.85

                if node.layer.animation(forKey: "transform.scale") != nil {
                    node.layer.removeAnimation(forKey: "transform.scale")
                }

                let anim = CAKeyframeAnimation(keyPath: "transform.scale")
                anim.values = [Float(currentScale), Float(maxScale), Float(minScale), Float(1.0)]
                anim.keyTimes = [0.0, 0.4, 0.8, 1.0]
                anim.duration = 0.5
                anim.timingFunction = CAMediaTimingFunction(name: .easeOut)

                node.layer.add(anim, forKey: "transform.scale")
                node.layer.transform = CATransform3DMakeScale(1.0, 1.0, 1.0)
            }

        case .ended:
            guard imageNode.layer.animation(forKey: "transform.scale") != nil else { break }

            for i in 0 ..< nodes.count {
                let node = nodes[i]
                let presentation = node.layer.presentation() ?? node.layer

                let t = presentation.transform
                let currentScale = sqrt((t.m11 * t.m11) + (t.m12 * t.m12) + (t.m13 * t.m13))

                if node.layer.animation(forKey: "transform.scale") != nil {
                    node.layer.removeAnimation(forKey: "transform.scale")
                }

                let anim = CABasicAnimation(keyPath: "transform.scale")
                anim.fromValue = NSNumber(value: Float(currentScale))
                anim.toValue = NSNumber(value: Float(1.0))
                anim.duration = 0.2
                anim.timingFunction = CAMediaTimingFunction(name: .easeOut)

                node.layer.add(anim, forKey: "transform.scale")
                node.layer.transform = CATransform3DMakeScale(1.0, 1.0, 1.0)
            }
        }
    }

    private func updateBackgroundState() {
        guard let callState = self.callState else { return }

        switch callState.state {
        case let .active(_, reception, _), let .reconnecting(_, reception, _):
            if let reception = reception, reception < 2 {
                backgroundNode.updateState(.weak)
            } else {
                backgroundNode.updateState(.active)
            }

        default:
            backgroundNode.updateState(.connecting)
        }

        guard !isAnimationsPaused else { return }
        guard !backgroundNode.isAnimating else { return }

        backgroundNode.startAnimating()
    }

    private func updateStatusToast() {
        guard let callState = self.callState else { return }

        var displayStatusToast: Bool = false
        switch callState.state {
        case let .active(_, reception, _), let .reconnecting(_, reception, _):
            if let reception = reception {
                displayStatusToast = reception < 2
            } else {
                displayStatusToast = false
            }
        default:
            break
        }

        guard displayingStatusToast != displayStatusToast else { return }
        displayingStatusToast = displayStatusToast

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)
        transition.updateAlpha(node: statusToastNode, alpha: displayStatusToast ? 1.0 : 0.0)

        if displayStatusToast {
            let animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.values = [Float(0.8), Float(1.05), Float(1.0)]
            animation.keyTimes = [0.0, 0.75, 1.0]
            animation.duration = 0.25
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            statusToastNode.layer.add(animation, forKey: "transform.scale")
        } else {
            statusToastNode.layer.animateScale(from: 1.0, to: 0.9, duration: 0.3, timingFunction: ContainedViewLayoutTransitionCurve.spring.timingFunction)
        }
    }
    
    private func updateToastContent() {
        guard let callState = self.callState else {
            return
        }
        if case .terminating = callState.state {
        } else if case .terminated = callState.state {
        } else {
            var toastContent: CallControllerToastContent = []
            if case .active = callState.state {
                if let displayToastsAfterTimestamp = self.displayToastsAfterTimestamp {
                    if CACurrentMediaTime() > displayToastsAfterTimestamp {
                        if case .inactive = callState.remoteVideoState, self.hasVideoNodes {
                            toastContent.insert(.camera)
                        }
                        if case .muted = callState.remoteAudioState {
                            toastContent.insert(.microphone)
                        }
                        if case .low = callState.remoteBatteryLevel {
                            toastContent.insert(.battery)
                        }
                    }
                } else {
                    self.displayToastsAfterTimestamp = CACurrentMediaTime() + 1.5
                }
            }
            if self.isMuted {
                toastContent.insert(.mute)
            }
            self.toastContent = toastContent
        }
    }
    
    private func updateDimVisibility(transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)) {
//        guard let callState = self.callState else {
//            return
//        }

//        var visible = true
//        if case .active = callState.state, self.incomingVideoNodeValue != nil || self.outgoingVideoNodeValue != nil {
//            visible = false
//        }

//        self.statusNode.setVisible(self.keyPreviewNode != nil, transition: transition)
    }

    private func updateAudioWaves() {
        guard let callState = callState else { return }

        switch callState.state {
        case .active:
            break

        case .terminating, .terminated:
            audioNode.animateOut()

        default:
            guard !isAnimationsPaused else { return }
            guard !audioNode.isAnimating else { return }

            audioNode.updateLevel(0.65)
            audioNode.startAnimating()
        }
    }

    private func updateAnimationsState(paused: Bool, force: Bool) {
        guard isAnimationsPaused != paused || force else { return }

        animationsPauseTimer?.invalidate()
        animationsPauseTimer = nil

        if paused {
            if force {
                isAnimationsPaused = true

                audioNode.stopAnimating()
                backgroundNode.stopAnimating()
            } else {
                let timer = SwiftSignalKit.Timer(timeout: 10.0, repeat: false, completion: { [weak self] in
                    guard let self = self else { return }

                    self.isAnimationsPaused = true
                    self.audioNode.stopAnimating()
                    self.backgroundNode.stopAnimating()

                    self.animationsPauseTimer?.invalidate()
                    self.animationsPauseTimer = nil
                }, queue: Queue.mainQueue())
                timer.start()
                animationsPauseTimer = timer
            }
        } else {
            isAnimationsPaused = false

            audioNode.startAnimating()
            backgroundNode.startAnimating()
        }
    }
    
    private func maybeScheduleUIHidingForActiveVideoCall() {
        guard let callState = self.callState, case .active = callState.state, self.incomingVideoNodeValue != nil && self.outgoingVideoNodeValue != nil, !self.hiddenUIForActiveVideoCallOnce && self.keyPreviewNode == nil else {
            return
        }
        
        let timer = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: { [weak self] in
            if let strongSelf = self {
                var updated = false
                if let callState = strongSelf.callState, !strongSelf.isUIHidden {
                    switch callState.state {
                        case .active, .connecting, .reconnecting:
                            strongSelf.isUIHidden = true
                            updated = true
                        default:
                            break
                    }
                }
                if updated, let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                }
                strongSelf.hideUIForActiveVideoCallTimer = nil
            }
        }, queue: Queue.mainQueue())
        timer.start()
        self.hideUIForActiveVideoCallTimer = timer
        self.hiddenUIForActiveVideoCallOnce = true
    }
    
    private func cancelScheduledUIHiding() {
        self.hideUIForActiveVideoCallTimer?.invalidate()
        self.hideUIForActiveVideoCallTimer = nil
    }
    
    private var buttonsTerminationMode: CallControllerButtonsMode?
    
    private func updateButtonsMode(transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)) {
        guard let callState = self.callState else {
            return
        }
        
        var mode: CallControllerButtonsSpeakerMode = .none
        var hasAudioRouteMenu: Bool = false
        if let (availableOutputs, maybeCurrentOutput) = self.audioOutputState, let currentOutput = maybeCurrentOutput {
            hasAudioRouteMenu = availableOutputs.count > 2
            switch currentOutput {
                case .builtin:
                    mode = .builtin
                case .speaker:
                    mode = .speaker
                case .headphones:
                    mode = .headphones
                case let .port(port):
                    var type: CallControllerButtonsSpeakerMode.BluetoothType = .generic
                    let portName = port.name.lowercased()
                    if portName.contains("airpods pro") {
                        type = .airpodsPro
                    } else if portName.contains("airpods") {
                        type = .airpods
                    }
                    mode = .bluetooth(type)
            }
            if availableOutputs.count <= 1 {
                mode = .none
            }
        }
        var mappedVideoState = CallControllerButtonsMode.VideoState(isAvailable: false, isCameraActive: self.outgoingVideoNodeValue != nil, isScreencastActive: false, canChangeStatus: false, hasVideo: self.outgoingVideoNodeValue != nil || self.incomingVideoNodeValue != nil, isInitializingCamera: self.isRequestingVideo)
        switch callState.videoState {
        case .notAvailable:
            break
        case .inactive:
            mappedVideoState.isAvailable = true
            mappedVideoState.canChangeStatus = true
        case .active(let isScreencast), .paused(let isScreencast):
            mappedVideoState.isAvailable = true
            mappedVideoState.canChangeStatus = true
            if isScreencast {
                mappedVideoState.isScreencastActive = true
                mappedVideoState.hasVideo = true
            }
        }
        
        switch callState.state {
        case .ringing:
            self.buttonsMode = .incoming(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .waiting, .requesting:
            self.buttonsMode = .outgoingRinging(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .active, .connecting, .reconnecting:
            self.buttonsMode = .active(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .terminating, .terminated:
            if let buttonsTerminationMode = self.buttonsTerminationMode {
                self.buttonsMode = buttonsTerminationMode
            } else {
                self.buttonsMode = .active(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            }
        }
                
        if let (layout, navigationHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: transition)
        }
    }
    
    func animateIn() {
        if !self.containerNode.alpha.isZero {
            var bounds = self.bounds
            bounds.origin = CGPoint()
            self.bounds = bounds
            self.layer.removeAnimation(forKey: "bounds")
            self.statusBar.layer.removeAnimation(forKey: "opacity")
            self.containerNode.layer.removeAnimation(forKey: "opacity")
            self.containerNode.layer.removeAnimation(forKey: "scale")
            self.statusBar.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            if !self.shouldStayHiddenUntilConnection {
                self.containerNode.layer.animateScale(from: 1.04, to: 1.0, duration: 0.3)
                self.containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            }
        }
    }
    
    func animateOut(completion: @escaping () -> Void) {
        self.statusBar.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
        if !self.shouldStayHiddenUntilConnection || self.containerNode.alpha > 0.0 {
            self.containerNode.layer.allowsGroupOpacity = true
            self.containerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak self] _ in
                self?.containerNode.layer.allowsGroupOpacity = false
            })
            self.containerNode.layer.animateScale(from: 1.0, to: 1.04, duration: 0.3, removeOnCompletion: false, completion: { _ in
                completion()
            })
        } else {
            completion()
        }
    }
    
    func expandFromPipIfPossible() {
        if self.pictureInPictureTransitionFraction.isEqual(to: 1.0), let (layout, navigationHeight) = self.validLayout {
            self.pictureInPictureTransitionFraction = 0.0
            
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
        }
    }
    
    private func calculatePreviewVideoRect(layout: ContainerViewLayout, navigationHeight: CGFloat, temporaryMinimizedNode: CallVideoNode? = nil) -> CGRect {
        let buttonsHeight: CGFloat = self.buttonsNode.bounds.height
        let toastHeight: CGFloat = self.toastNode.bounds.height
        let toastInset = (toastHeight > 0.0 ? toastHeight + 16.0 : 0.0)
        
        var fullInsets = layout.insets(options: .statusBar)
    
        var cleanInsets = fullInsets
        cleanInsets.bottom = max(layout.intrinsicInsets.bottom, 20.0) + toastInset
        cleanInsets.left = 10.0
        cleanInsets.right = 10.0
        
        fullInsets.top += 44.0 + 8.0
        fullInsets.bottom = buttonsHeight + 16.0 + toastInset
        fullInsets.left = 10.0
        fullInsets.right = 10.0
        
        var insets: UIEdgeInsets = self.isUIHidden ? cleanInsets : fullInsets
        
        let expandedInset: CGFloat = 6.0
        
        insets.top = interpolate(from: expandedInset, to: insets.top, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.bottom = interpolate(from: expandedInset, to: insets.bottom, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.left = interpolate(from: expandedInset, to: insets.left, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.right = interpolate(from: expandedInset, to: insets.right, value: 1.0 - self.pictureInPictureTransitionFraction)

        let previewScale: CGFloat = !isUIHidden ? 1.0 : (14.0 / 24.0)
        let previewVideoSide = interpolate(from: 300.0, to: (240.0 / 393.0) * layout.size.width * previewScale, value: 1.0 - self.pictureInPictureTransitionFraction)
        var previewVideoSize = layout.size.aspectFitted(CGSize(width: previewVideoSide, height: previewVideoSide))
        previewVideoSize = CGSize(width: 30.0, height: 52.0).aspectFitted(previewVideoSize)

        if let minimizedVideoNode = temporaryMinimizedNode ?? self.minimizedVideoNode {
            var aspect = minimizedVideoNode.currentAspect
            var rotationCount = 0
            if minimizedVideoNode === self.outgoingVideoNodeValue {
                aspect = 9.0 / 16.0
            } else {
                if aspect < 1.0 {
                    aspect = 9.0 / 16.0
                } else {
                    aspect = 16.0 / 9.0
                }
                
                switch minimizedVideoNode.currentOrientation {
                case .rotation90, .rotation270:
                    rotationCount += 1
                default:
                    break
                }
                
                var mappedDeviceOrientation = self.deviceOrientation
                if case .regular = layout.metrics.widthClass, case .regular = layout.metrics.heightClass {
                    mappedDeviceOrientation = .portrait
                }
                
                switch mappedDeviceOrientation {
                case .landscapeLeft, .landscapeRight:
                    rotationCount += 1
                default:
                    break
                }
                
                if rotationCount % 2 != 0 {
                    aspect = 1.0 / aspect
                }
            }
            
            let unboundVideoSize = CGSize(width: aspect * 10000.0, height: 10000.0)
            
            previewVideoSize = unboundVideoSize.aspectFitted(CGSize(width: previewVideoSide, height: previewVideoSide))
        }
        let previewVideoY: CGFloat
        let previewVideoX: CGFloat
        
        switch self.outgoingVideoNodeCorner {
        case .topLeft:
            previewVideoX = insets.left
            previewVideoY = insets.top
        case .topRight:
            previewVideoX = layout.size.width - previewVideoSize.width - insets.right
            previewVideoY = insets.top
        case .bottomLeft:
            previewVideoX = insets.left
            previewVideoY = layout.size.height - insets.bottom - previewVideoSize.height
        case .bottomRight:
            previewVideoX = layout.size.width - previewVideoSize.width - insets.right
            previewVideoY = layout.size.height - insets.bottom - previewVideoSize.height
        }
        
        return CGRect(origin: CGPoint(x: previewVideoX, y: previewVideoY), size: previewVideoSize)
    }
    
    private func calculatePictureInPictureContainerRect(layout: ContainerViewLayout, navigationHeight: CGFloat) -> CGRect {
        let pictureInPictureTopInset: CGFloat = layout.insets(options: .statusBar).top + 44.0 + 8.0
        let pictureInPictureSideInset: CGFloat = 8.0
        let pictureInPictureSize = layout.size.fitted(CGSize(width: 240.0, height: 240.0))
        let pictureInPictureBottomInset: CGFloat = layout.insets(options: .input).bottom + 44.0 + 8.0
        
        let containerPictureInPictureFrame: CGRect
        switch self.pictureInPictureCorner {
        case .topLeft:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: pictureInPictureSideInset, y: pictureInPictureTopInset), size: pictureInPictureSize)
        case .topRight:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: layout.size.width -  pictureInPictureSideInset - pictureInPictureSize.width, y: pictureInPictureTopInset), size: pictureInPictureSize)
        case .bottomLeft:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: pictureInPictureSideInset, y: layout.size.height - pictureInPictureBottomInset - pictureInPictureSize.height), size: pictureInPictureSize)
        case .bottomRight:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: layout.size.width -  pictureInPictureSideInset - pictureInPictureSize.width, y: layout.size.height - pictureInPictureBottomInset - pictureInPictureSize.height), size: pictureInPictureSize)
        }
        return containerPictureInPictureFrame
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationBarHeight)
        
        var mappedDeviceOrientation = self.deviceOrientation
        var isCompactLayout = true
        if case .regular = layout.metrics.widthClass, case .regular = layout.metrics.heightClass {
            mappedDeviceOrientation = .portrait
            isCompactLayout = false
        }
        
        if !self.hasVideoNodes {
            self.isUIHidden = false
        }
        
        var isUIHidden = self.isUIHidden
        switch self.callState?.state {
        case .terminated, .terminating:
            isUIHidden = false
        default:
            break
        }
        
        var uiDisplayTransition: CGFloat = isUIHidden ? 0.0 : 1.0
        let pipTransitionAlpha: CGFloat = 1.0 - self.pictureInPictureTransitionFraction
        uiDisplayTransition *= pipTransitionAlpha
        
        let pinchTransitionAlpha: CGFloat = self.isVideoPinched ? 0.0 : 1.0
        
        let previousVideoButtonFrame = self.buttonsNode.videoButtonFrame().flatMap { frame -> CGRect in
            return self.buttonsNode.view.convert(frame, to: self.view)
        }
        
        let buttonsHeight: CGFloat
        if let buttonsMode = self.buttonsMode {
            buttonsHeight = self.buttonsNode.updateLayout(strings: self.presentationData.strings, mode: buttonsMode, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom + 34.0, transition: transition)
        } else {
            buttonsHeight = 0.0
        }
        let defaultButtonsOriginY = layout.size.height - buttonsHeight
        let buttonsCollapsedOriginY = self.pictureInPictureTransitionFraction > 0.0 ? layout.size.height + 30.0 : layout.size.height + 10.0
        let buttonsOriginY = interpolate(from: buttonsCollapsedOriginY, to: defaultButtonsOriginY, value: uiDisplayTransition)
        
        let toastHeight = self.toastNode.updateLayout(strings: self.presentationData.strings, content: self.toastContent, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom + buttonsHeight, transition: transition)
        
        let toastSpacing: CGFloat = 22.0
        let toastCollapsedOriginY = self.pictureInPictureTransitionFraction > 0.0 ? layout.size.height : layout.size.height - max(layout.intrinsicInsets.bottom, 20.0) - toastHeight
        let toastOriginY = interpolate(from: toastCollapsedOriginY, to: defaultButtonsOriginY - toastSpacing - toastHeight, value: uiDisplayTransition)

        let topPanelTransition: ContainedViewLayoutTransition
        if case .active = callState?.state, !displayedActiveStateOnce {
            displayedActiveStateOnce = true
            topPanelTransition = .animated(duration: 0.5, curve: .spring)
        } else {
            topPanelTransition = transition
        }

        var topPanelAlpha: CGFloat = displayedActiveStateOnce ? min(pinchTransitionAlpha, uiDisplayTransition) : 0.0
        let statusAlpha: CGFloat = min(pinchTransitionAlpha, uiDisplayTransition)
        var overlayAlpha: CGFloat = min(pinchTransitionAlpha, uiDisplayTransition)
        var toastAlpha: CGFloat = min(pinchTransitionAlpha, pipTransitionAlpha)

        switch self.callState?.state {
        case .terminated, .terminating:
            topPanelAlpha = 0.0
            overlayAlpha = 0.0
            toastAlpha = 0.0
        default:
            break
        }
        
        let containerFullScreenFrame = CGRect(origin: CGPoint(), size: layout.size)
        let containerPictureInPictureFrame = self.calculatePictureInPictureContainerRect(layout: layout, navigationHeight: navigationBarHeight)
        
        let containerFrame = interpolateFrame(from: containerFullScreenFrame, to: containerPictureInPictureFrame, t: self.pictureInPictureTransitionFraction)
        
        transition.updateFrame(node: self.containerTransformationNode, frame: containerFrame)
        transition.updateSublayerTransformScale(node: self.containerTransformationNode, scale: min(1.0, containerFrame.width / layout.size.width * 1.01))
        transition.updateCornerRadius(layer: self.containerTransformationNode.layer, cornerRadius: self.pictureInPictureTransitionFraction * 10.0)

        transition.updateFrame(node: backgroundNode, frame: containerFullScreenFrame)
        backgroundNode.updateLayout(containerFullScreenFrame.size, transition: transition)
        
        transition.updateFrame(node: self.containerNode, frame: CGRect(origin: CGPoint(x: (containerFrame.width - layout.size.width) / 2.0, y: floor(containerFrame.height - layout.size.height) / 2.0), size: layout.size))
        transition.updateFrame(node: self.videoContainerNode, frame: containerFullScreenFrame)
        self.videoContainerNode.update(size: containerFullScreenFrame.size, transition: transition)
        
        if let keyPreviewNode = self.keyPreviewNode {
            transition.updateFrame(node: keyPreviewNode, frame: containerFullScreenFrame)
            keyPreviewNode.updateLayout(size: layout.size, transition: .immediate)
        }
        
        let navigationOffset: CGFloat = max(20.0, layout.safeInsets.top)
        let navigationHeight: CGFloat = 44.0
        let topOriginY = interpolate(from: -20.0, to: navigationOffset, value: uiDisplayTransition)

        let backArrowOffset: CGFloat = displayedActiveStateOnce ? 0.0 : 15.0
        let backButtonOffset: CGFloat = displayedActiveStateOnce ? 0.0 : 35.0
        
        let backSize = self.backButtonNode.measure(CGSize(width: 320.0, height: 100.0))
        if let image = self.backButtonArrowNode.image {
            topPanelTransition.updateFrame(node: self.backButtonArrowNode, frame: CGRect(origin: CGPoint(x: 10.0 + backArrowOffset, y: topOriginY + 11.0), size: image.size))
        }
        topPanelTransition.updateFrame(node: self.backButtonNode, frame: CGRect(origin: CGPoint(x: 29.0 + backButtonOffset, y: topOriginY + 11.0), size: backSize))

        topPanelTransition.updateAlpha(node: self.backButtonArrowNode, alpha: topPanelAlpha)
        topPanelTransition.updateAlpha(node: self.backButtonNode, alpha: topPanelAlpha)
        transition.updateAlpha(node: self.statusNode, alpha: statusAlpha)
        transition.updateAlpha(node: self.toastNode, alpha: toastAlpha)

        let imageSide = layout.size.width / 3.0
        let imageSize = CGSize(width: imageSide, height: imageSide)

        let statusOffset: CGFloat = 20.0
        let statusHeight = self.statusNode.updateLayout(constrainedWidth: layout.size.width, transition: transition)

        let imageStatusOffset: CGFloat = 10.0
        let imageStatusHeight: CGFloat = imageSize.height + statusOffset + statusHeight
        let imageFrame = CGRect(origin: CGPoint(x: (layout.size.width - imageSize.width) / 2.0, y: max(topOriginY, ((layout.size.height - buttonsHeight) - imageStatusHeight) / 2.0 - imageStatusOffset)), size: imageSize)
        transition.updateFrame(node: self.imageNode, frame: imageFrame)
        transition.updateCornerRadius(node: self.imageNode, cornerRadius: imageSide / 2.0)
        let imageSizeCeiled = CGSize(width: ceil(imageSize.width), height: ceil(imageSize.height))
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: imageSizeCeiled, boundingSize: imageSizeCeiled, intrinsicInsets: UIEdgeInsets())
        let apply = self.imageNode.asyncLayout()(arguments)
        apply()

        let audioSize = CGSize(width: layout.size.width, height: layout.size.width)
        let audioFrame = CGRect(origin: CGPoint(x: imageFrame.midX - audioSize.width / 2.0, y: imageFrame.midY - audioSize.height / 2.0), size: audioSize)
        transition.updateFrameAsPositionAndBounds(node: audioNode, frame: audioFrame)
        audioNode.updateLayout(audioFrame.size, transition: transition)

        let hasVideoNodes = incomingVideoNodeValue != nil || outgoingVideoNodeValue != nil
        let statusFrame: CGRect
        if hasVideoNodes {
            statusFrame = CGRect(origin: CGPoint(x: 0.0, y: topOriginY + navigationHeight), size: CGSize(width: layout.size.width, height: statusHeight))
        } else {
            statusFrame = CGRect(origin: CGPoint(x: 0.0, y: imageFrame.maxY + statusOffset), size: CGSize(width: layout.size.width, height: statusHeight))
        }
        transition.updateFrameAsPositionAndBounds(node: self.statusNode, frame: statusFrame)

        let statusToastSize = statusToastNode.updateLayout(CGSize(width: layout.size.width - 32.0, height: 50.0), transition: transition)
        let statusToastFrame = CGRect(origin: CGPoint(x: (layout.size.width - statusToastSize.width) / 2.0, y: statusFrame.maxY + 10.0), size: statusToastSize)
        transition.updateFrameAsPositionAndBounds(node: statusToastNode, frame: statusToastFrame)

        let closeAvailableWidth: CGFloat = layout.size.width - 44.0 * 2.0
        let closeHeight: CGFloat = closeContainerNode.updateLayout(CGSize(width: closeAvailableWidth, height: 50.0), transition: .immediate)
        let closeOriginY: CGFloat = defaultButtonsOriginY + 3.0
        let closeFrame = CGRect(origin: CGPoint(x: 44.0, y: closeOriginY), size: CGSize(width: closeAvailableWidth, height: closeHeight))
        transition.updateFrame(node: closeContainerNode, frame: closeFrame)

        let ratingAvailableWidth: CGFloat = layout.size.width - 44.0 * 2.0
        let ratingHeight = ratingNode.updateLayout(ratingAvailableWidth)
        let ratingOffset: CGFloat = layout.intrinsicInsets.bottom > 0.0 ? 66.0 : 50.0
        let ratingFrame = CGRect(origin: CGPoint(x: 44.0, y: closeFrame.minY - ratingOffset - ratingHeight), size: CGSize(width: ratingAvailableWidth, height: ratingHeight))
        transition.updateFrameAsPositionAndBounds(node: self.ratingNode, frame: ratingFrame)
        
        transition.updateFrame(node: self.toastNode, frame: CGRect(origin: CGPoint(x: 0.0, y: toastOriginY), size: CGSize(width: layout.size.width, height: toastHeight)))
        transition.updateFrame(node: self.buttonsNode, frame: CGRect(origin: CGPoint(x: 0.0, y: buttonsOriginY), size: CGSize(width: layout.size.width, height: buttonsHeight)))
        transition.updateAlpha(node: self.buttonsNode, alpha: overlayAlpha)
        
        let fullscreenVideoFrame = containerFullScreenFrame
        let previewVideoFrame = self.calculatePreviewVideoRect(layout: layout, navigationHeight: navigationBarHeight)
        
        if let removedMinimizedVideoNodeValue = self.removedMinimizedVideoNodeValue {
            self.removedMinimizedVideoNodeValue = nil
            
            if transition.isAnimated {
                removedMinimizedVideoNodeValue.layer.animateScale(from: 1.0, to: 0.8, duration: 0.2, removeOnCompletion: false)
                removedMinimizedVideoNodeValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak removedMinimizedVideoNodeValue] _ in
                    removedMinimizedVideoNodeValue?.removeFromSupernode()
                })
            } else {
                removedMinimizedVideoNodeValue.removeFromSupernode()
            }
        }
        
        if let expandedVideoNode = self.expandedVideoNode {
            transition.updateAlpha(node: expandedVideoNode, alpha: 1.0)
            var expandedVideoTransition = transition
            var animateExpandedVideoNode: Bool = false

            if expandedVideoNode.frame.isEmpty || self.disableAnimationForExpandedVideoOnce {
                expandedVideoTransition = .immediate
                animateExpandedVideoNode = minimizedVideoNode == nil
                self.disableAnimationForExpandedVideoOnce = false
            }
            
            if let removedExpandedVideoNodeValue = self.removedExpandedVideoNodeValue {
                self.removedExpandedVideoNodeValue = nil
                
                expandedVideoTransition.updateFrame(node: expandedVideoNode, frame: fullscreenVideoFrame, completion: { [weak removedExpandedVideoNodeValue] _ in
                    removedExpandedVideoNodeValue?.removeFromSupernode()
                })
            } else {
                expandedVideoTransition.updateFrame(node: expandedVideoNode, frame: fullscreenVideoFrame)
            }
            
            expandedVideoNode.updateLayout(size: expandedVideoNode.frame.size, cornerRadius: 0.0, isOutgoing: expandedVideoNode === self.outgoingVideoNodeValue, deviceOrientation: mappedDeviceOrientation, isCompactLayout: isCompactLayout, transition: expandedVideoTransition)
            
            if self.animateRequestedVideoOnce, animateExpandedVideoNode {
                self.animateRequestedVideoOnce = false
                if expandedVideoNode === self.outgoingVideoNodeValue {
                    let videoButtonFrame = self.buttonsNode.videoButtonFrame().flatMap { frame -> CGRect in
                        return self.buttonsNode.view.convert(frame, to: self.view)
                    }
                    
                    if let previousVideoButtonFrame = previousVideoButtonFrame, let videoButtonFrame = videoButtonFrame {
                        expandedVideoNode.animateRadialMask(from: previousVideoButtonFrame, to: videoButtonFrame)
                    }
                } else if expandedVideoNode === self.incomingVideoNodeValue {
                    expandedVideoNode.animateRoundedRect(from: imageFrame, fromCornerRadius: imageSide / 2.0, to: fullscreenVideoFrame, toCornerRadius: layout.deviceMetrics.screenCornerRadius)
                }
            } else {
                self.animateRequestedVideoOnce = false
            }
        } else if let removedExpandedVideoNodeValue = self.removedExpandedVideoNodeValue {
            self.removedExpandedVideoNodeValue = nil

            if transition.isAnimated {
                imageNode.layer.animateScale(from: 1.3, to: 1.0, duration: 0.1, delay: 0.2, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue)
                removedExpandedVideoNodeValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.1, delay: 0.2, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false)
                removedExpandedVideoNodeValue.animateRoundedRect(from: fullscreenVideoFrame, fromCornerRadius: layout.deviceMetrics.screenCornerRadius, to: imageFrame, toCornerRadius: imageSide / 2.0) { [weak removedExpandedVideoNodeValue] in
                    removedExpandedVideoNodeValue?.removeFromSupernode()
                }
            } else {
                removedExpandedVideoNodeValue.removeFromSupernode()
            }
        }
        
        
        if let minimizedVideoNode = self.minimizedVideoNode {
            transition.updateAlpha(node: minimizedVideoNode, alpha: min(pipTransitionAlpha, pinchTransitionAlpha))
            var minimizedVideoTransition = transition
            var didAppear = false
            if minimizedVideoNode.frame.isEmpty || self.animationSnapshotExist {
                minimizedVideoTransition = .immediate
                didAppear = true
            }
            if self.minimizedVideoDraggingPosition == nil {
                var needBounceAnimation: Bool = false
                if let animationSnapshotMinimizedView = self.animationSnapshotMinimizedView {
                    self.videoContainerNode.contentNode.view.addSubview(animationSnapshotMinimizedView)
                    transition.updateAlpha(layer: animationSnapshotMinimizedView.layer, alpha: 0.0, completion: { [weak animationSnapshotMinimizedView] _ in
                        animationSnapshotMinimizedView?.removeFromSuperview()
                    })

                    minimizedVideoNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
                    needBounceAnimation = true
                }
                if let animationSnapshotExpandedView = animationSnapshotExpandedView, let expandedVideoNode = expandedVideoNode {
                    self.videoContainerNode.contentNode.view.insertSubview(animationSnapshotExpandedView, aboveSubview: expandedVideoNode.view)
                    transition.updateAlpha(layer: animationSnapshotExpandedView.layer, alpha: 0.0) { [weak animationSnapshotExpandedView] _ in
                        animationSnapshotExpandedView?.removeFromSuperview()
                    }
                    needBounceAnimation = true
                }
                minimizedVideoTransition.updateFrame(node: minimizedVideoNode, frame: previewVideoFrame)
                minimizedVideoNode.updateLayout(size: previewVideoFrame.size, cornerRadius: interpolate(from: 14.0, to: 24.0, value: self.pictureInPictureTransitionFraction), isOutgoing: minimizedVideoNode === self.outgoingVideoNodeValue, deviceOrientation: mappedDeviceOrientation, isCompactLayout: layout.metrics.widthClass == .compact, transition: minimizedVideoTransition)
                if transition.isAnimated && didAppear && needBounceAnimation {
                    let animation = CAKeyframeAnimation(keyPath: "transform.scale")
                    animation.duration = 0.2
                    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    animation.values = [1.0, 0.9, 1.0]
                    minimizedVideoNode.layer.add(animation, forKey: "transform.scale")
                    animationSnapshotMinimizedView?.layer.add(animation, forKey: "transform.scale")
                }
            }

            self.animationSnapshotMinimizedView = nil
            self.animationSnapshotExpandedView = nil
        }
        
        let keyTextSize = self.keyButtonNode.frame.size
        transition.updateFrame(node: self.keyButtonNode, frame: CGRect(origin: CGPoint(x: layout.size.width - keyTextSize.width - 8.0, y: topOriginY + 8.0), size: keyTextSize))
        transition.updateAlpha(node: self.keyButtonNode, alpha: overlayAlpha)
        
        if let debugNode = self.debugNode {
            transition.updateFrame(node: debugNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        }
        
        let requestedAspect: CGFloat
        if case .compact = layout.metrics.widthClass, case .compact = layout.metrics.heightClass {
            var isIncomingVideoRotated = false
            var rotationCount = 0
            
            switch mappedDeviceOrientation {
            case .portrait:
                break
            case .landscapeLeft:
                rotationCount += 1
            case .landscapeRight:
                rotationCount += 1
            case .portraitUpsideDown:
                 break
            default:
                break
            }
            
            if rotationCount % 2 != 0 {
                isIncomingVideoRotated = true
            }
            
            if !isIncomingVideoRotated {
                requestedAspect = layout.size.width / layout.size.height
            } else {
                requestedAspect = 0.0
            }
        } else {
            requestedAspect = 0.0
        }
        if self.currentRequestedAspect != requestedAspect {
            self.currentRequestedAspect = requestedAspect
            if !self.sharedContext.immediateExperimentalUISettings.disableVideoAspectScaling {
                self.call.setRequestedVideoAspect(Float(requestedAspect))
            }
        }
    }
    
    @objc func keyPressed() {
        if self.keyPreviewNode == nil, let keyText = self.keyTextData?.1, let peer = self.peer {
            let keyPreviewNode = CallControllerKeyPreviewNode(keyText: keyText, infoText: self.presentationData.strings.Call_EmojiDescription(EnginePeer(peer).compactDisplayTitle).string.replacingOccurrences(of: "%%", with: "%"), dismiss: { [weak self] in
                if let _ = self?.keyPreviewNode {
                    self?.backPressed()
                }
            })
            
            self.containerNode.insertSubnode(keyPreviewNode, belowSubnode: self.statusNode)
            self.keyPreviewNode = keyPreviewNode
            
            if let (validLayout, _) = self.validLayout {
                keyPreviewNode.updateLayout(size: validLayout.size, transition: .immediate)
                
                self.keyButtonNode.isHidden = true
                keyPreviewNode.animateIn(from: self.keyButtonNode.frame, fromNode: self.keyButtonNode)
            }
            
            self.updateDimVisibility()
        }
    }
    
    @objc func backPressed() {
        if let keyPreviewNode = self.keyPreviewNode {
            self.keyPreviewNode = nil
            keyPreviewNode.animateOut(to: self.keyButtonNode.frame, toNode: self.keyButtonNode, completion: { [weak self, weak keyPreviewNode] in
                self?.keyButtonNode.isHidden = false
                keyPreviewNode?.removeFromSupernode()
            })
            self.updateDimVisibility()
        } else if self.hasVideoNodes {
            if let (layout, navigationHeight) = self.validLayout {
                self.pictureInPictureTransitionFraction = 1.0
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
            }
        } else {
            self.back?()
        }
    }
    
    private var hasVideoNodes: Bool {
        return self.expandedVideoNode != nil || self.minimizedVideoNode != nil
    }
    
    private var debugTapCounter: (Double, Int) = (0.0, 0)
    
    private func areUserActionsDisabledNow() -> Bool {
        return CACurrentMediaTime() < self.disableActionsUntilTimestamp
    }
    
    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            if !self.pictureInPictureTransitionFraction.isZero {
                self.view.window?.endEditing(true)
                
                if let (layout, navigationHeight) = self.validLayout {
                    self.pictureInPictureTransitionFraction = 0.0
                    
                    self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                }
            } else if let _ = self.keyPreviewNode {
                self.backPressed()
            } else {
                if self.hasVideoNodes {
                    let point = recognizer.location(in: recognizer.view)
                    if let expandedVideoNode = self.expandedVideoNode, let minimizedVideoNode = self.minimizedVideoNode, minimizedVideoNode.frame.contains(point) {
                        if !self.areUserActionsDisabledNow() {
                            let minimizedCopyView = minimizedVideoNode.view.snapshotView(afterScreenUpdates: false)
                            minimizedCopyView?.frame = minimizedVideoNode.frame

                            let expandedCopyView = expandedVideoNode.view.snapshotView(afterScreenUpdates: false)
                            expandedCopyView?.frame = expandedVideoNode.frame

                            self.expandedVideoNode = minimizedVideoNode
                            self.minimizedVideoNode = expandedVideoNode
                            if let supernode = expandedVideoNode.supernode {
                                supernode.insertSubnode(expandedVideoNode, aboveSubnode: minimizedVideoNode)
                            }
                            self.disableActionsUntilTimestamp = CACurrentMediaTime() + 0.3
                            if let (layout, navigationBarHeight) = self.validLayout {
                                self.disableAnimationForExpandedVideoOnce = true
                                self.animationSnapshotMinimizedView = minimizedCopyView
                                self.animationSnapshotExpandedView = expandedCopyView
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }
                    } else {
                        var updated = false
                        if let callState = self.callState {
                            switch callState.state {
                            case .active, .connecting, .reconnecting:
                                self.isUIHidden = !self.isUIHidden
                                updated = true
                            default:
                                break
                            }
                        }
                        if updated, let (layout, navigationBarHeight) = self.validLayout {
                            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                        }
                    }
                } else {
                    let point = recognizer.location(in: recognizer.view)
                    if self.statusNode.frame.contains(point) {
                        if self.easyDebugAccess {
                            self.presentDebugNode()
                        } else {
                            let timestamp = CACurrentMediaTime()
                            if self.debugTapCounter.0 < timestamp - 0.75 {
                                self.debugTapCounter.0 = timestamp
                                self.debugTapCounter.1 = 0
                            }
                            
                            if self.debugTapCounter.0 >= timestamp - 0.75 {
                                self.debugTapCounter.0 = timestamp
                                self.debugTapCounter.1 += 1
                            }
                            
                            if self.debugTapCounter.1 >= 10 {
                                self.debugTapCounter.1 = 0
                                
                                self.presentDebugNode()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func presentDebugNode() {
        guard self.debugNode == nil else {
            return
        }
        
        self.forceReportRating = true
        
        let debugNode = CallDebugNode(signal: self.debugInfo)
        debugNode.dismiss = { [weak self] in
            if let strongSelf = self {
                strongSelf.debugNode?.removeFromSupernode()
                strongSelf.debugNode = nil
            }
        }
        self.addSubnode(debugNode)
        self.debugNode = debugNode
        
        if let (layout, navigationBarHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
    }
    
    private var minimizedVideoInitialPosition: CGPoint?
    private var minimizedVideoDraggingPosition: CGPoint?
    
    private func nodeLocationForPosition(layout: ContainerViewLayout, position: CGPoint, velocity: CGPoint) -> VideoNodeCorner {
        let layoutInsets = UIEdgeInsets()
        var result = CGPoint()
        if position.x < layout.size.width / 2.0 {
            result.x = 0.0
        } else {
            result.x = 1.0
        }
        if position.y < layoutInsets.top + (layout.size.height - layoutInsets.bottom - layoutInsets.top) / 2.0 {
            result.y = 0.0
        } else {
            result.y = 1.0
        }
        
        let currentPosition = result
        
        let angleEpsilon: CGFloat = 30.0
        var shouldHide = false
        
        if (velocity.x * velocity.x + velocity.y * velocity.y) >= 500.0 * 500.0 {
            let x = velocity.x
            let y = velocity.y
            
            var angle = atan2(y, x) * 180.0 / CGFloat.pi * -1.0
            if angle < 0.0 {
                angle += 360.0
            }
            
            if currentPosition.x.isZero && currentPosition.y.isZero {
                if ((angle > 0 && angle < 90 - angleEpsilon) || angle > 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                } else if (angle > 180 + angleEpsilon && angle < 270 + angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                } else if (angle > 270 + angleEpsilon && angle < 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                } else {
                    shouldHide = true
                }
            } else if !currentPosition.x.isZero && currentPosition.y.isZero {
                if (angle > 90 + angleEpsilon && angle < 180 + angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (angle > 270 - angleEpsilon && angle < 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                }
                else if (angle > 180 + angleEpsilon && angle < 270 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                }
                else {
                    shouldHide = true
                }
            } else if currentPosition.x.isZero && !currentPosition.y.isZero {
                if (angle > 90 - angleEpsilon && angle < 180 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (angle < angleEpsilon || angle > 270 + angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                }
                else if (angle > angleEpsilon && angle < 90 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                }
                else if (!shouldHide) {
                    shouldHide = true
                }
            } else if !currentPosition.x.isZero && !currentPosition.y.isZero {
                if (angle > angleEpsilon && angle < 90 + angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                }
                else if (angle > 180 - angleEpsilon && angle < 270 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                }
                else if (angle > 90 + angleEpsilon && angle < 180 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (!shouldHide) {
                    shouldHide = true
                }
            }
        }
        
        if result.x.isZero {
            if result.y.isZero {
                return .topLeft
            } else {
                return .bottomLeft
            }
        } else {
            if result.y.isZero {
                return .topRight
            } else {
                return .bottomRight
            }
        }
    }
    
    @objc private func panGesture(_ recognizer: CallPanGestureRecognizer) {
        switch recognizer.state {
            case .began:
                guard let location = recognizer.firstLocation else {
                    return
                }
                if self.pictureInPictureTransitionFraction.isZero, let expandedVideoNode = self.expandedVideoNode, let minimizedVideoNode = self.minimizedVideoNode, minimizedVideoNode.frame.contains(location), expandedVideoNode.frame != minimizedVideoNode.frame {
                    self.minimizedVideoInitialPosition = minimizedVideoNode.position
                } else if self.hasVideoNodes {
                    self.minimizedVideoInitialPosition = nil
                    if !self.pictureInPictureTransitionFraction.isZero {
                        self.pictureInPictureGestureState = .dragging(initialPosition: self.containerTransformationNode.position, draggingPosition: self.containerTransformationNode.position)
                    } else {
                        self.pictureInPictureGestureState = .collapsing(didSelectCorner: false)
                    }
                } else {
                    self.pictureInPictureGestureState = .none
                }
                self.dismissAllTooltips?()
            case .changed:
                if let minimizedVideoNode = self.minimizedVideoNode, let minimizedVideoInitialPosition = self.minimizedVideoInitialPosition {
                    let translation = recognizer.translation(in: self.view)
                    let minimizedVideoDraggingPosition = CGPoint(x: minimizedVideoInitialPosition.x + translation.x, y: minimizedVideoInitialPosition.y + translation.y)
                    self.minimizedVideoDraggingPosition = minimizedVideoDraggingPosition
                    minimizedVideoNode.position = minimizedVideoDraggingPosition
                } else {
                    switch self.pictureInPictureGestureState {
                    case .none:
                        let offset = recognizer.translation(in: self.view).y
                        var bounds = self.bounds
                        bounds.origin.y = -offset
                        self.bounds = bounds
                    case let .collapsing(didSelectCorner):
                        if let (layout, navigationHeight) = self.validLayout {
                            let offset = recognizer.translation(in: self.view)
                            if !didSelectCorner {
                                self.pictureInPictureGestureState = .collapsing(didSelectCorner: true)
                                if offset.x < 0.0 {
                                    self.pictureInPictureCorner = .topLeft
                                } else {
                                    self.pictureInPictureCorner = .topRight
                                }
                            }
                            let maxOffset: CGFloat = min(300.0, layout.size.height / 2.0)
                            
                            let offsetTransition = max(0.0, min(1.0, abs(offset.y) / maxOffset))
                            self.pictureInPictureTransitionFraction = offsetTransition
                            switch self.pictureInPictureCorner {
                            case .topRight, .bottomRight:
                                self.pictureInPictureCorner = offset.y < 0.0 ? .topRight : .bottomRight
                            case .topLeft, .bottomLeft:
                                self.pictureInPictureCorner = offset.y < 0.0 ? .topLeft : .bottomLeft
                            }
                            
                            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
                        }
                    case .dragging(let initialPosition, var draggingPosition):
                        let translation = recognizer.translation(in: self.view)
                        draggingPosition.x = initialPosition.x + translation.x
                        draggingPosition.y = initialPosition.y + translation.y
                        self.pictureInPictureGestureState = .dragging(initialPosition: initialPosition, draggingPosition: draggingPosition)
                        self.containerTransformationNode.position = draggingPosition
                    }
                }
            case .cancelled, .ended:
                if let minimizedVideoNode = self.minimizedVideoNode, let _ = self.minimizedVideoInitialPosition, let minimizedVideoDraggingPosition = self.minimizedVideoDraggingPosition {
                    self.minimizedVideoInitialPosition = nil
                    self.minimizedVideoDraggingPosition = nil
                    
                    if let (layout, navigationHeight) = self.validLayout {
                        self.outgoingVideoNodeCorner = self.nodeLocationForPosition(layout: layout, position: minimizedVideoDraggingPosition, velocity: recognizer.velocity(in: self.view))
                        
                        let videoFrame = self.calculatePreviewVideoRect(layout: layout, navigationHeight: navigationHeight)
                        minimizedVideoNode.frame = videoFrame
                        minimizedVideoNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: minimizedVideoDraggingPosition.x - videoFrame.midX, y: minimizedVideoDraggingPosition.y - videoFrame.midY)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, delay: 0.0, initialVelocity: 0.0, damping: 110.0, removeOnCompletion: true, additive: true, completion: nil)
                    }
                } else {
                    switch self.pictureInPictureGestureState {
                    case .none:
                        let velocity = recognizer.velocity(in: self.view).y
                        if abs(velocity) < 100.0 {
                            var bounds = self.bounds
                            let previous = bounds
                            bounds.origin = CGPoint()
                            self.bounds = bounds
                            self.layer.animateBounds(from: previous, to: bounds, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
                        } else {
                            var bounds = self.bounds
                            let previous = bounds
                            bounds.origin = CGPoint(x: 0.0, y: velocity > 0.0 ? -bounds.height: bounds.height)
                            self.bounds = bounds
                            self.layer.animateBounds(from: previous, to: bounds, duration: 0.15, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, completion: { [weak self] _ in
                                self?.dismissedInteractively?()
                            })
                        }
                    case .collapsing:
                        self.pictureInPictureGestureState = .none
                        let velocity = recognizer.velocity(in: self.view).y
                        if abs(velocity) < 100.0 && self.pictureInPictureTransitionFraction < 0.5 {
                            if let (layout, navigationHeight) = self.validLayout {
                                self.pictureInPictureTransitionFraction = 0.0
                                
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                            }
                        } else {
                            if let (layout, navigationHeight) = self.validLayout {
                                self.pictureInPictureTransitionFraction = 1.0
                                
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                            }
                        }
                    case let .dragging(initialPosition, _):
                        self.pictureInPictureGestureState = .none
                        if let (layout, navigationHeight) = self.validLayout {
                            let translation = recognizer.translation(in: self.view)
                            let draggingPosition = CGPoint(x: initialPosition.x + translation.x, y: initialPosition.y + translation.y)
                            self.pictureInPictureCorner = self.nodeLocationForPosition(layout: layout, position: draggingPosition, velocity: recognizer.velocity(in: self.view))
                            
                            let containerFrame = self.calculatePictureInPictureContainerRect(layout: layout, navigationHeight: navigationHeight)
                            self.containerTransformationNode.frame = containerFrame
                            containerTransformationNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: draggingPosition.x - containerFrame.midX, y: draggingPosition.y - containerFrame.midY)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, delay: 0.0, initialVelocity: 0.0, damping: 110.0, removeOnCompletion: true, additive: true, completion: nil)
                        }
                    }
                }
            default:
                break
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let event = event, event.type == .touches, !hasVideoNodes {
            updateAnimationsState(paused: false, force: true)
        }

        if self.debugNode != nil {
            return super.hitTest(point, with: event)
        }
        if self.containerTransformationNode.frame.contains(point) {
            return self.containerTransformationNode.view.hitTest(self.view.convert(point, to: self.containerTransformationNode.view), with: event)
        }
        return nil
    }
}

final class CallPanGestureRecognizer: UIPanGestureRecognizer {
    private(set) var firstLocation: CGPoint?
    
    public var shouldBegin: ((CGPoint) -> Bool)?
    
    override public init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        
        self.maximumNumberOfTouches = 1
    }
    
    override public func reset() {
        super.reset()
        
        self.firstLocation = nil
    }
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        let touch = touches.first!
        let point = touch.location(in: self.view)
        if let shouldBegin = self.shouldBegin, !shouldBegin(point) {
            self.state = .failed
            return
        }
        
        self.firstLocation = point
    }
    
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
    }
}
