import UIKit

private let availableCommitTime: CFTimeInterval = 1.0 / CFTimeInterval(UIScreen.main.maximumFramesPerSecond) / 2.0
private let availableCommitXxsTime: CFTimeInterval = availableCommitTime / 16.0
private let availableCommitXsTime: CFTimeInterval = availableCommitTime / 8.0
private let availableCommitSTime: CFTimeInterval = availableCommitTime / 4.0
private let availableCommitMTime: CFTimeInterval = availableCommitTime / 2.0
private let availableCommitLTime: CFTimeInterval = availableCommitTime

public func conditionerDisplayed(weight: DisplayLinkConditioner.BlockWeight, immediate: Bool, isOutdated: @escaping () -> Bool, block: @escaping () -> Void) {
    if immediate {
        block()
    } else {
        DisplayLinkConditioner.shared.add(weight: weight, isOutdated: isOutdated, block: block)
    }
}

public final class DisplayLinkConditioner {
    // MARK: - Children

    public enum BlockWeight {
        // MARK: - Cases

        case xxs    // 16 operations in one draw cycle < 0.5 ms for 1 block on 60 fps
        case xs     // 8  operations in one draw cycle < 1 ms for 1 block on 60 fps
        case s      // 4  operations in one draw cycle < 2 ms for 1 block on 60 fps
        case m      // 2  operations in one draw cycle < 4 ms for 1 block on 60 fps
        case l      // 1  operation  in one draw cycle < 8 ms for 1 block on 60 fps

        // MARK: - Properties

        var maxTime: CFTimeInterval {
            switch self {
            case .xxs:
                return availableCommitXxsTime
            case .xs:
                return availableCommitXsTime
            case .s:
                return availableCommitSTime
            case .m:
                return availableCommitMTime
            case .l:
                return availableCommitLTime
            }
        }
    }

    private struct Block {
        // MARK: - Properties

        let work: () -> Void
        let isOutdated: () -> Bool
        let weight: BlockWeight
    }

    // MARK: - Static

    static public let shared = DisplayLinkConditioner()

    // MARK: - Properties

    private var displayLink: SharedDisplayLinkDriver.Link?
    private var blocks: [Block] = []

    // MARK: - Interface

    public func add(weight: BlockWeight, isOutdated: @escaping () -> Bool, block: @escaping () -> Void) {
        assert(Thread.isMainThread)
        blocks.append(Block(work: block, isOutdated: isOutdated, weight: weight))

        updateDisplayLinkIfNeeded()
    }

    // MARK: - Private. Life Cycle

    private func update() {
        let beginTime = CACurrentMediaTime()

        var currentTime: CFTimeInterval = 0.0
        while let block = enqueueNext(currentTime: currentTime) {
            let beginTime = CACurrentMediaTime()
            block.work()
            let blockTime = CACurrentMediaTime() - beginTime
            currentTime += blockTime
        }

        #if DEBUG
        let executionTime = CACurrentMediaTime() - beginTime
        if executionTime > availableCommitTime {
            print("conditioner warning -- too much time to draw, hitch duration: \(executionTime - availableCommitTime)")
        }
        #endif

        updateDisplayLinkIfNeeded()
    }

    // MARK: - Private. Help

    private func updateDisplayLinkIfNeeded() {
        if !blocks.isEmpty {
            if let displayLink = displayLink, displayLink.isPaused {
                displayLink.isPaused = false
            } else if displayLink == nil {
                displayLink = SharedDisplayLinkDriver.shared.add { [weak self] in
                    self?.update()
                }
            }
        } else {
            #if DEBUG
            print("pause display link conditioner")
            #endif
            displayLink?.isPaused = true
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func enqueueNext(currentTime: CFTimeInterval) -> Block? {
        guard !blocks.isEmpty else { return nil }

        var block: Block? = blocks[0]
        while let b = block, b.isOutdated() {
            _ = blocks.removeFirst()

            if blocks.isEmpty {
                return nil
            } else {
                block = blocks[0]
            }
        }

        guard currentTime + blocks[0].weight.maxTime <= availableCommitTime else { return nil }
        return blocks.removeFirst()
    }
}
