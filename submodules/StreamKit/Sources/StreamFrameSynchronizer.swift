//
//  StreamFrameSynchronizer.swift
//  StreamKit
//
//  Created by Nikita Bondar on 19.10.2024.
//

import CoreMedia
import SwiftSignalKit

final class StreamFrameSynchronizer {
    // MARK: - Children

    enum Frame {
        // MARK: - Case

        case frame(MediaTrackFrame)
        case noFrames
        case waiting
    }

    private final class Storage {
        // MARK: - Properties

        private var frames: [StreamSessionManifestContent: [MediaTrackFrame]] = [:]
        private var times: [StreamSessionManifestContent: CMTime] = [:]

        // MARK: - Interface

        func frame(for content: StreamSessionManifestContent) -> Frame {
            if frames[content] != nil, !frames[content]!.isEmpty {
                let time = readTime() ?? .zero
                while !frames[content]!.isEmpty {
                    let frame = frames[content]![0]
                    let lowerTimeBound = frame.position.seconds - 0.1
                    let upperTimeBound = frame.position.seconds + frame.duration.seconds + 0.1

                    if time.seconds < lowerTimeBound {
                        return .waiting
                    }

                    if lowerTimeBound <= time.seconds, time.seconds <= upperTimeBound {
                        frames[content]!.removeFirst()
                        updateTime()
                        return .frame(frame)
                    }

                    if time.seconds > upperTimeBound {
                        frames[content]!.removeFirst()
                    }
                }
            }
            return .noFrames
        }

        func add(frames: [MediaTrackFrame], for content: StreamSessionManifestContent) -> Self {
            if self.frames[content] != nil {
                self.frames[content]?.append(contentsOf: frames)
            } else {
                self.frames[content] = frames
            }
            updateTime()
            return self
        }

        func clean() -> Self {
            frames = [:]
            times = [:]
            return self
        }

        // MARK: - Private. Help

        private func readTime() -> CMTime? {
            let priorities: [StreamSessionManifestContent] = [.video, .audio, .subtitles]
            for priority in priorities {
                if let time = times[priority] {
                    return time
                }
            }
            return nil
        }

        private func updateTime() {
            let priorities: [StreamSessionManifestContent] = [.video, .audio, .subtitles]
            for priority in priorities {
                if let frame = frames[priority]?.first {
                    times[priority] = frame.position
                }
            }
        }
    }

    // MARK: - Properties

    private let storage: Atomic<Storage>

    // MARK: - Init

    init() {
        storage = Atomic(value: Storage())
    }

    // MARK: - Interface

    func frame(for content: StreamSessionManifestContent) -> Frame {
        storage.with { storage in
            storage.frame(for: content)
        }
    }

    func add(frames: [MediaTrackFrame], for content: StreamSessionManifestContent) {
        _ = storage.modify { storage in
            storage.add(frames: frames, for: content)
        }
    }

    func clean() {
        _ = storage.modify { storage in
            storage.clean()
        }
    }
}

private extension StreamSessionManifestContent {
    // MARK: - Properties

    var key: String {
        switch self {
        case .audio:
            return "audio"
        case .subtitles:
            return "subtitles"
        case .video:
            return "video"
        }
    }
}
