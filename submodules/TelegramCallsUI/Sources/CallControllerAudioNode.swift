import AsyncDisplayKit
import Display
import SwiftSignalKit
import UIKit

private let white = UIColor(rgb: 0xffffff)
private let greyColor = UIColor(rgb: 0x2c2c2e)
private let secondaryGreyColor = UIColor(rgb: 0x1c1c1e)
private let blue = UIColor(rgb: 0x007fff)
private let lightBlue = UIColor(rgb: 0x00affe)
private let green = UIColor(rgb: 0x33c659)
private let activeBlue = UIColor(rgb: 0x00a0b9)
private let purple = UIColor(rgb: 0x3252ef)
private let pink = UIColor(rgb: 0xef436c)

private let areaSize = CGSize(width: 300.0, height: 300.0)
private let blobSize = CGSize(width: 190.0, height: 190.0)

private let buttonSize = CGSize(width: 112.0, height: 112.0)
private let buttonHeight: CGFloat = 52.0
private let radius = buttonSize.width / 2.0

private final class CallControllerAudioBlobView: UIView {
    // MARK: - Properties

    public typealias BlobRange = (min: CGFloat, max: CGFloat)

    private let maxLevel: CGFloat

    var presentationAudioLevel: CGFloat = 0.0
    private var audioLevel: CGFloat = 0.0

    var scaleUpdated: ((CGFloat) -> Void)? {
        didSet {
            self.bigBlob.scaleUpdated = self.scaleUpdated
        }
    }

    private(set) var isAnimating = false

    private let hierarchyTrackingNode: HierarchyTrackingNode
    private var isCurrentlyInHierarchy = true

    private var displayLinkAnimator: ConstantDisplayLinkAnimator?

    // MARK: - Views

    private let mediumBlob: BlobView
    private let bigBlob: BlobView

    // MARK: - Init

    init(
        frame: CGRect,
        maxLevel: CGFloat,
        mediumBlobRange: BlobRange,
        bigBlobRange: BlobRange
    ) {
        var updateInHierarchy: ((Bool) -> Void)?
        self.hierarchyTrackingNode = HierarchyTrackingNode({ value in
            updateInHierarchy?(value)
        })

        self.maxLevel = maxLevel

        self.mediumBlob = BlobView(
            pointsCount: 8,
            minRandomness: 1,
            maxRandomness: 1,
            minSpeed: 0.9,
            maxSpeed: 4.0,
            minScale: mediumBlobRange.min,
            maxScale: mediumBlobRange.max
        )
        self.bigBlob = BlobView(
            pointsCount: 8,
            minRandomness: 1,
            maxRandomness: 1,
            minSpeed: 1.0,
            maxSpeed: 4.4,
            minScale: bigBlobRange.min,
            maxScale: bigBlobRange.max
        )

        super.init(frame: frame)

        addSubnode(hierarchyTrackingNode)

        addSubview(bigBlob)
        addSubview(mediumBlob)

        displayLinkAnimator = ConstantDisplayLinkAnimator() { [weak self] in
            guard let strongSelf = self else { return }

            if !strongSelf.isCurrentlyInHierarchy {
                return
            }

            strongSelf.presentationAudioLevel = strongSelf.presentationAudioLevel * 0.9 + strongSelf.audioLevel * 0.1

            strongSelf.mediumBlob.level = strongSelf.presentationAudioLevel
            strongSelf.bigBlob.level = strongSelf.presentationAudioLevel
        }

        updateInHierarchy = { [weak self] value in
            if let strongSelf = self {
                strongSelf.isCurrentlyInHierarchy = value
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Life cycle

    override func layoutSubviews() {
        super.layoutSubviews()

        mediumBlob.frame = bounds
        bigBlob.frame = bounds

        updateBlobsState()
    }

    // MARK: - Interface

    func setColor(_ color: UIColor) {
        mediumBlob.setColor(color.withAlphaComponent(0.5))
        bigBlob.setColor(color.withAlphaComponent(0.21))
    }

    func updateLevel(_ level: CGFloat, immediately: Bool) {
        let normalizedLevel = min(1, max(level / maxLevel, 0))

        mediumBlob.updateSpeedLevel(to: normalizedLevel)
        bigBlob.updateSpeedLevel(to: normalizedLevel)

        audioLevel = normalizedLevel
        if immediately {
            presentationAudioLevel = normalizedLevel
        }
    }

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true

        updateBlobsState()

        displayLinkAnimator?.isPaused = false
    }

    func stopAnimating() {
        self.stopAnimating(duration: 0.15)
    }

    func stopAnimating(duration: Double) {
        guard isAnimating else { return }
        isAnimating = false

        updateBlobsState()

        displayLinkAnimator?.isPaused = true
    }

    // MARK: - Private. Help

    private func updateBlobsState() {
        if isAnimating {
            if mediumBlob.frame.size != .zero {
                mediumBlob.startAnimating()
                bigBlob.startAnimating()
            }
        } else {
            mediumBlob.stopAnimating()
            bigBlob.stopAnimating()
        }
    }
}

final class CallControllerAudioNode: ASDisplayNode {
    // MARK: - Properties

    private var isAnimatingOut: Bool = false
    private var isAnimatedOut: Bool = false

    private var audioLevelDisposable: Disposable?

    // MARK: - Nodes

    private let blobView: CallControllerAudioBlobView

    // MARK: - Init

    override init() {
        blobView = CallControllerAudioBlobView(
            frame: CGRect(origin: .zero, size: blobSize),
            maxLevel: 1.5,
            mediumBlobRange: (0.69, 0.87),
            bigBlobRange: (0.71, 1.0)
        )

        super.init()

        blobView.setColor(white)
    }

    deinit {
        audioLevelDisposable?.dispose()
    }

    // MARK: - Life cycle

    override func didLoad() {
        super.didLoad()

        view.addSubview(blobView)
    }

    func updateLayout(_ size: CGSize, transition: ContainedViewLayoutTransition) {
        let identityWidth: CGFloat = 375.0
        let aspect = size.width / identityWidth
        let blobSize = CGSize(width: blobSize.width * aspect, height: blobSize.height * aspect)
        let blobFrame = CGRect(origin: CGPoint(x: (size.width - blobSize.width) / 2.0, y: (size.height - blobSize.height) / 2.0), size: blobSize)
        let previousBlobFrame = blobView.frame
        transition.updateFrameAsPositionAndBounds(layer: blobView.layer, frame: blobFrame)

        if blobFrame.size != previousBlobFrame.size {
            blobView.layoutSubviews()
        }
    }

    // MARK: - Interface

    func startAnimating() {
        blobView.startAnimating()
    }

    func stopAnimating() {
        blobView.stopAnimating()
    }

    func setSignal(_ signal: Signal<Float, NoError>) {
        audioLevelDisposable = signal.start { [weak self] value in
            guard let self = self else { return }
            self.blobView.updateLevel(CGFloat(value), immediately: false)
        }
    }

    func updateLevel(_ level: CGFloat) {
        blobView.updateLevel(level, immediately: false)
    }

    func animateOut() {
        guard !isAnimatingOut else { return }
        guard !isAnimatedOut else { return }

        isAnimatingOut = true

        let alphaTransition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)
        alphaTransition.updateAlpha(layer: blobView.layer, alpha: 0.0)

        let scaleTransition: ContainedViewLayoutTransition = .animated(duration: 0.6, curve: .spring)
        scaleTransition.updateTransformScale(layer: blobView.layer, scale: 0.7) { [weak self] _ in
            self?.isAnimatingOut = false
            self?.isAnimatedOut = true
            self?.blobView.stopAnimating()
        }
    }
}
