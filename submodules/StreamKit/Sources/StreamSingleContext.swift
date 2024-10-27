//
//  StreamSingleContext.swift
//  StreamKit
//
//  Created by Nikita Bondar on 26.10.2024.
//

import CoreMedia
import SwiftSignalKit

private final class FrameBuffer {
    // MARK: - Properties

    var count: Int {
        frames.count
    }

    private var frames: [MediaTrackFrame] = []

    // MARK: - Init

    init(capacity: Int) {
        frames.reserveCapacity(capacity * 2)
    }

    // MARK: - Interface

    func insert(_ frames: [MediaTrackFrame]) {
        self.frames.append(contentsOf: frames)
        self.frames.sort { $0.position < $1.position }
    }

    func drop() -> MediaTrackFrame? {
        if !frames.isEmpty {
            return frames.removeFirst()
        }
        return nil
    }

    func dropAll() {
        if !frames.isEmpty {
            frames = []
        }
    }
}

final class StreamSingleContext: StreamContext {
    // MARK: - Children

    private final class Child {
        // MARK: - Properties

        var ended: Bool = false
        let header: StreamHeaderFile
        let reader: StreamContextSingleReader

        // MARK: - Init

        init(header: StreamHeaderFile, reader: StreamContextSingleReader) {
            self.header = header
            self.reader = reader
        }
    }

    private final class State {
        // MARK: - Properties

        private(set) var children: [Child] = []
        private var childrenKey: Set<AnyHashable> = []

        let frameBuffer: FrameBuffer

        // MARK: - Init

        init(frameBuffer: FrameBuffer) {
            self.frameBuffer = frameBuffer
        }

        // MARK: - Interface

        func contains(child: Child) -> Bool {
            childrenKey.contains(child.header.id)
        }

        func add(child: Child) {
            guard !childrenKey.contains(child.header.id) else { return }
            childrenKey.insert(child.header.id)
            children.append(child)
        }

        func remove(child: Child) {
            childrenKey.remove(child.header.id)
            if let index = children.firstIndex(where: { $0.header.id == child.header.id }) {
                children.remove(at: index)
            }
        }
    }

    // MARK: - Properties

    var fpsUpdated: ((CMTime) -> Void)?
    private var fps: CMTime?

    private let state: Atomic<State>
    private let framesGopCount: Int
    private let queue: Queue

    private var afterUpdatingChildActions: [() -> Void] = []
    private var updatingChild = false
    private var cancelUpdatingChild = false

    // MARK: - Init

    init(gopCount: Int, queue: Queue) {
        self.framesGopCount = gopCount
        state = Atomic(value: State(frameBuffer: FrameBuffer(capacity: gopCount)))
        self.queue = queue
    }

    // MARK: - Interface

    func readFrame(completion: ((MediaTrackFrame?) -> Void)?) {
        state.with { state in
            let frame = state.frameBuffer.drop()
            if state.frameBuffer.count < framesGopCount {
                queue.async { self.generateFrames() }
            }
            completion?(frame)
        }
    }

    func readFrame() -> MediaTrackFrame? {
        state.with { state in
            let frame = state.frameBuffer.drop()
            if state.frameBuffer.count < framesGopCount {
                queue.async { self.generateFrames() }
            }
            return frame
        }
    }

    func add(_ files: [StreamSegmentFile]) {
        state.with { state in
            if let child = state.children.first {
                child.reader.add(files)
            }
        }
        queue.async { [weak self] in
            self?.generateFrames()
        }
    }

    func add(_ header: StreamHeaderFile) {
        var update = false
        state.with { _ in
            guard !updatingChild else { return }
            update = true
            updatingChild = true
            cancelUpdatingChild = false
        }

        if update {
            Queue.concurrentDefaultQueue().async { [weak self] in
                guard let self else { return }

                var actions: [() -> Void] = []
                let child = Child(header: header, reader: StreamContextSingleReader(headerPath: header.path))
                self.state.with { state in
                    if !self.cancelUpdatingChild {
                        state.add(child: child)
                    }
                    self.updatingChild = false
                    self.cancelUpdatingChild = false

                    actions = self.afterUpdatingChildActions
                    self.afterUpdatingChildActions = []
                }

                self.queue.async {
                    actions.forEach { $0() }
                }
            }
        } else {
            state.with { _ in
                afterUpdatingChildActions.append { [weak self] in
                    guard let self else { return }
                    self.add(header)
                }
            }
        }
    }

    func clean() {
        state.with { state in
            cancelUpdatingChild = true
            state.children.forEach { state.remove(child: $0) }
            state.frameBuffer.dropAll()
        }
    }

    // MARK: - Private. Help

    private func generateFrames() {
        var maybeChild: Child?
        var frameBufferCount: Int = 0
        state.with { maybeChild = $0.children.first; frameBufferCount = $0.frameBuffer.count }

        guard let child = maybeChild, frameBufferCount < framesGopCount else { return }

        let (frames, ended) = child.reader.readFrames(count: max(1, framesGopCount - frameBufferCount))
        child.ended = ended

        if frames.isEmpty {
//            state.with { $0.remove(child: child) }
//            return generateFrames()
            return
        }

        if let contextInfo = child.reader.contextInfo() {
            if let videoStream = contextInfo.videoStream, fps != videoStream.fps {
                self.fps = videoStream.fps
                fpsUpdated?(videoStream.fps)
            }

            var decoded: [MediaTrackFrame] = []
            for frame in frames {
                guard let decoder = frame.type == .audio ? contextInfo.audioStream?.decoder : contextInfo.videoStream?.decoder else { continue }

                if let decodedFrame = decoder.decode(frame: frame) {
                    decoded.append(decodedFrame)
                }
            }

            state.with { state in
                guard state.contains(child: child) else { return }
                state.frameBuffer.insert(decoded)
            }
        }

        queue.justDispatch { [weak self] in
            self?.generateFrames()
        }
    }
}
