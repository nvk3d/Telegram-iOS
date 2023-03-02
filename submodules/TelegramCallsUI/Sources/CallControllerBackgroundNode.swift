import AsyncDisplayKit
import Display
import GradientBackground

final class CallControllerBackgroundNode: ASDisplayNode {
    // MARK: - Children

    enum State {
        // MARK: - Cases

        case active
        case connecting
        case weak
    }

    // MARK: - Properties

    private(set) var isAnimating: Bool = false
    private(set) var state: State = .connecting

    private var animateWhenReady: Bool = false
    private var animationInProgress: Bool = false
    private var validSize: CGSize?

    private var needColorsUpdating: Bool = false
    private var colorsUpdating: Bool { colorsAnimator != nil }
    private var colorsToUpdate: (start: [UIColor], end: [UIColor])?
    private var colorsAnimator: DisplayLinkAnimator?

    // MARK: - Nodes

    private let gradientNode: GradientBackgroundNode

    // MARK: - Init

    override init() {
        gradientNode = GradientBackgroundNode(colors: [])

        super.init()

        gradientNode.updateColors(colors: colors(for: state))
        addSubnode(gradientNode)
    }

    deinit {
        colorsAnimator?.invalidate()
    }

    // MARK: - Life cycle

    func updateLayout(_ size: CGSize, transition: ContainedViewLayoutTransition) {
        validSize = size

        transition.updateFrame(node: gradientNode, frame: CGRect(origin: .zero, size: size))
        gradientNode.updateLayout(size: size, transition: transition, extendAnimation: false, backwards: false, completion: {})

        if animateWhenReady {
            animateWhenReady = false
            animateEvent()
        }
    }

    // MARK: - Interface

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true

        if validSize == nil {
            animateWhenReady = true
        } else {
            animateEvent()
        }
    }

    func stopAnimating() {
        isAnimating = false
        animateWhenReady = false
    }

    func updateState(_ state: State) {
        guard self.state != state else { return }

        let oldState = self.state
        self.state = state

        needColorsUpdating = true
        colorsToUpdate = (start: colors(for: oldState), end: colors(for: state))

        if isAnimating {
            gradientNode.stopAllAnimationsAndSavePresentation()
        } else {
            updateColors()
        }
    }

    // MARK: - Private. Help

    private func animateEvent(transition: ContainedViewLayoutTransition = .animated(duration: 0.7, curve: .linear), extendAnimation: Bool = false) {
        guard validSize != nil else { return }
        guard !animationInProgress else { return }

        animationInProgress = true
        gradientNode.animateEvent(transition: transition, extendAnimation: extendAnimation, backwards: false) { [weak self] in
            guard let self = self else { return }
            self.animationInProgress = false

            guard self.isAnimating else { return }

            if self.needColorsUpdating {
                self.updateColors()
            } else {
                self.animateEvent(transition: transition, extendAnimation: extendAnimation)
            }
        }
    }

    private func colors(for state: State) -> [UIColor] {
        switch state {
        case .active:
            return [
                UIColor(rgb: 0x3C9C8F),
                UIColor(rgb: 0xBAC05D),
                UIColor(rgb: 0x398D6F),
                UIColor(rgb: 0x53A6DE)
            ]

        case .connecting:
            return [
                UIColor(rgb: 0x7261DA),
                UIColor(rgb: 0xAC65D4),
                UIColor(rgb: 0x616AD5),
                UIColor(rgb: 0x5295D6)
            ]

        case .weak:
            return [
                UIColor(rgb: 0xFF7E46),
                UIColor(rgb: 0xC94986),
                UIColor(rgb: 0xF4992E),
                UIColor(rgb: 0xB84498)
            ]
        }
    }

    private func updateColors() {
        guard let colorsToUpdate = colorsToUpdate else { return }

        let start = colorsToUpdate.start
        let end = colorsToUpdate.end

        colorsAnimator?.invalidate()
        colorsAnimator = DisplayLinkAnimator(duration: 0.3, from: 0.0, to: 1.0, update: { [weak self] progress in
            guard let self = self else { return }

            var colors: [UIColor] = []
            for i in 0 ..< start.count {
                guard let startComponents = self.getComponents(start[i]) else { continue }
                guard let endComponents = self.getComponents(end[i]) else { continue }

                let intermediate = UIColor(
                    red: startComponents.r + (endComponents.r - startComponents.r) * progress,
                    green: startComponents.g + (endComponents.g - startComponents.g) * progress,
                    blue: startComponents.b + (endComponents.b - startComponents.b) * progress,
                    alpha: startComponents.a + (endComponents.a - startComponents.a) * progress
                )
                colors.append(intermediate)
            }

            self.gradientNode.updateColors(colors: colors)
        }, completion: { [weak self] in
            guard let self = self else { return }

            self.colorsAnimator = nil
            self.colorsToUpdate = nil
            self.needColorsUpdating = false

            if self.isAnimating {
                self.animateEvent()
            }
        })
    }

    private func getComponents(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0

        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (r: red, g: green, b: blue, a: alpha)
        } else {
            return nil
        }
    }
}
