import AccountContext
import AsyncDisplayKit
import Display
import DrawingUI
import CallsEmoji
import TelegramCore
import UIKit

private let labelFont = Font.regular(40.0)

private class EmojiSlotNode: ASDisplayNode {
    var emoji: String = "" {
        didSet {
            self.node.attributedText = NSAttributedString(string: emoji, font: labelFont, textColor: .black)
            updateLayout()
        }
    }

    var entity: DrawingStickerEntity? {
        didSet {
            stickerView?.removeFromSuperview()
            stickerView = nil

            if let context = context, let entity = entity {
                let view = entity.makeView(context: context)
                view.frame = CGRect(origin: .zero, size: CGSize(width: 48.0, height: 48.0))
                containerNode.view.addSubview(view)
                stickerView = view
                updateLayout()
            }
        }
    }

    private let context: AccountContext?

    private let containerNode: ASDisplayNode
    private let node: ImmediateTextNode
    private var stickerView: DrawingEntityView?
    
    init(context: AccountContext?) {
        self.context = context
        self.containerNode = ASDisplayNode()
        self.node = ImmediateTextNode()
                    
        super.init()

        self.addSubnode(self.containerNode)
        self.containerNode.addSubnode(self.node)
    }

    func updateLayout() {
        let containerSize = bounds.size
        let containerFrame = CGRect(origin: .zero, size: containerSize)
        containerNode.layer.position = CGPoint(x: containerFrame.midX, y: containerFrame.midY)
        containerNode.layer.bounds = CGRect(origin: .zero, size: containerSize)

        let nodeSize = node.updateLayout(CGSize(width: 100.0, height: 100.0))
        let nodeFrame = CGRect(origin: CGPoint(x: (containerSize.width - nodeSize.width) / 2.0, y: (containerSize.height - nodeSize.height) / 2.0), size: nodeSize)
        node.layer.position = CGPoint(x: nodeFrame.midX, y: nodeFrame.midY)
        node.layer.bounds = CGRect(origin: .zero, size: nodeSize)

        stickerView?.layer.position = CGPoint(x: containerSize.width / 2.0, y: containerSize.height / 2.0)
        stickerView?.layer.bounds = CGRect(origin: .zero, size: CGSize(width: 48.0, height: 48.0))
        stickerView?.layoutSubviews()
    }
}

final class CallControllerKeyButton: HighlightableButtonNode {
    enum AnimatingSource {
        case source(AccountContext, [String: [StickerPackItem]])
        case none
    }

    private var source: AnimatingSource = .none
    private var scaled: Bool = false

    private let containerNode: ASDisplayNode
    private let nodes: [EmojiSlotNode]
    
    var key: String = "" {
        didSet {
            var animated: [String: [StickerPackItem]] = [:]

            switch source {
            case let .source(_, emojis):
                animated = emojis
            case .none:
                break
            }

            var entities: [DrawingStickerEntity] = []
            var index = 0
            for emoji in key {
                guard index < 4 else { break }

                if let pack = animated[String(emoji)], let file = pack.first?.file {
                    entities.append(DrawingStickerEntity(content: .file(file)))
                    index += 1
                } else {
                    break
                }
            }

            if entities.count == 4 {
                for (i, entity) in entities.enumerated() {
                    self.nodes[i].entity = entity
                }
            } else {
                index = 0
                for emoji in key {
                    guard index < 4 else { break }

                    self.nodes[index].emoji = String(emoji)
                    index += 1
                }
            }
        }
    }
    
    init(source: AnimatingSource = .none) {
        self.containerNode = ASDisplayNode()
        var context: AccountContext?
        if case let .source(ctx, _) = source {
            context = ctx
        }
        self.nodes = (0 ..< 4).map { _ in EmojiSlotNode(context: context) }

        self.source = source
       
        super.init(pointerStyle: nil)

        containerNode.layer.anchorPoint = CGPoint(x: 1.0, y: 0.0)
        self.addSubnode(self.containerNode)
        self.nodes.forEach({ self.containerNode.addSubnode($0) })

        ContainedViewLayoutTransition.immediate.updateTransformScale(layer: containerNode.layer, scale: 0.5)
    }
        
    func animateIn(_ transition: ContainedViewLayoutTransition) {
        let nodeSize: CGSize = CGSize(width: 48.0, height: 48.0)
        let interitemInset: CGFloat = 4.0
        var duration: Double = 0.0
        var timingFunction: String = ""
        if case let .animated(d, c) = transition {
            duration = d
            timingFunction = c.timingFunction
        }

        var delta: CGFloat = nodeSize.width / 2.0
        for node in self.nodes.reversed() {
            let position = node.layer.position
            node.layer.animatePosition(from: CGPoint(x: position.x - delta, y: position.y), to: position, duration: duration, timingFunction: timingFunction)
            delta += interitemInset + nodeSize.width / 2.0
        }
    }

    func scale(value: Bool, transition: ContainedViewLayoutTransition) {
        scaled = value
        transition.updateTransformScale(node: containerNode, scale: value ? 1.0 : 0.5)
    }

    override func measure(_ constrainedSize: CGSize) -> CGSize {
        scaled ? CGSize(width: 224.0, height: 68.0) : CGSize(width: 122.0, height: 44.0)
    }

    func updateLayout() {
        let containerSize = CGSize(width: 48.0 * 4.0 + 4.0 * 3.0, height: 48.0)
        containerNode.layer.position = CGPoint(x: bounds.width - 10.0, y: 10.0)
        containerNode.layer.bounds = CGRect(origin: .zero, size: containerSize)

        let nodeSize = CGSize(width: 48.0, height: 48.0)
        let interitemInset: CGFloat = 4.0
        var offsetX: CGFloat = 0.0

        for node in self.nodes {
            let frame = CGRect(origin: CGPoint(x: offsetX, y: 0.0), size: nodeSize)
            node.position = CGPoint(x: frame.midX, y: frame.midY)
            node.bounds = CGRect(origin: .zero, size: frame.size)
            node.updateLayout()

            offsetX += nodeSize.width + interitemInset
        }
    }
}
