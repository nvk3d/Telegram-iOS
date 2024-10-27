//
//  StreamMultipleContext.swift
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

final class StreamMultipleContext: StreamContext {
    // MARK: - Children

    private final class Child {
        // MARK: - Properties

        var ended: Bool = false
        let file: StreamSegmentFile
        let reader: StreamContextMultipleReader

        // MARK: - Init

        init(file: StreamSegmentFile, reader: StreamContextMultipleReader) {
            self.file = file
            self.reader = reader
        }
    }

    private final class State {
        // MARK: - Properties

        private(set) var children: [Child] = []
        private var childrenKey: Set<AnyHashable> = []

        let frameBuffer: FrameBuffer
        var completion: ((MediaTrackFrame?) -> Void)?

        // MARK: - Init

        init(frameBuffer: FrameBuffer) {
            self.frameBuffer = frameBuffer
        }

        // MARK: - Interface

        func contains(child: Child) -> Bool {
            childrenKey.contains(child.file.id)
        }

        func add(child: Child) {
            guard !childrenKey.contains(child.file.id) else { return }
            childrenKey.insert(child.file.id)
            children.append(child)
        }

        func remove(child: Child) {
            childrenKey.remove(child.file.id)
            if let index = children.firstIndex(where: { $0.file.id == child.file.id }) {
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

    private var files: [StreamSegmentFile] = []
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
            if let frame = frame {
                completion?(frame)
            } else {
                state.completion = completion
            }
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
            self.files.append(contentsOf: files)
        }
        updateChildrenIfNeeded()
    }

    func add(_ header: StreamHeaderFile) {}

    func clean() {
        state.with { state in
            cancelUpdatingChild = true
            state.children.forEach { state.remove(child: $0) }
            state.frameBuffer.dropAll()
            files.removeAll()
        }
    }

    // MARK: - Private. Help

    private func generateFrames() {
        var maybeChild: Child?
        var maybeCompletion: ((MediaTrackFrame?) -> Void)?
        var frameBufferCount: Int = 0
        state.with { maybeChild = $0.children.first; frameBufferCount = $0.frameBuffer.count; maybeCompletion = $0.completion }

        guard let child = maybeChild else { return }

        if frameBufferCount >= framesGopCount {
            if let completion = maybeCompletion {
                state.with { state in
                    state.completion = nil
                    completion(state.frameBuffer.drop())
                }
            }
            return
        }

        let (frames, ended) = child.reader.readFrames(count: max(1, framesGopCount - frameBufferCount))
        child.ended = ended

        if frames.isEmpty {
            state.with { $0.remove(child: child) }
            updateChildrenIfNeeded()
            return generateFrames()
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

            var update = false
            state.with { state in
                guard state.contains(child: child) else { return }
                state.frameBuffer.insert(decoded)
                update = state.frameBuffer.count < framesGopCount

                if !update, let completion = state.completion {
                    state.completion = nil
                    completion(state.frameBuffer.drop())
                }
            }

            if update {
                updateChildrenIfNeeded()
            }
        }

        queue.justDispatch { [weak self] in
            self?.generateFrames()
        }
    }

    private func updateChildrenIfNeeded() {
        var file: StreamSegmentFile?
        state.with { state in
            guard !updatingChild, state.children.filter({ !$0.ended }).count < 3, !files.isEmpty else { return }
            updatingChild = true
            cancelUpdatingChild = false
            file = files.removeFirst()
        }

        if let file = file {
            Queue.concurrentDefaultQueue().async { [weak self] in
                guard let self else { return }

                let child = Child(file: file, reader: StreamContextMultipleReader(path: file.path))
                self.state.with { state in
                    if !self.cancelUpdatingChild {
                        let generate = state.children.isEmpty
                        state.add(child: child)

                        if generate {
                            self.queue.async { self.generateFrames() }
                        }
                    }
                    self.updatingChild = false
                    self.cancelUpdatingChild = false
                }
            }
        }
    }
}
