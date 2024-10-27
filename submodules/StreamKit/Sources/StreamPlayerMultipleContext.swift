//
//  StreamPlayerMultipleContext.swift
//  StreamKit
//
//  Created by Nikita Bondar on 26.10.2024.
//

import CoreMedia
import Foundation
import SwiftSignalKit

final class StreamPlayerMultipleContext: StreamPlayerContext {
    // MARK: - Properties

    var fpsUpdated: ((CMTime) -> Void)?

    private let audioContext: StreamContext
    private let videoContext: StreamContext

    // MARK: - Init

    init() {
        let contextQueue = Queue()

        audioContext = StreamMultipleContext(gopCount: 20, queue: contextQueue)

        videoContext = StreamMultipleContext(gopCount: 15, queue: contextQueue)
        videoContext.fpsUpdated = { [weak self] fps in
            guard let self else { return }
            self.fpsUpdated?(fps)
        }
    }

    // MARK: - Interface

    func readFrame(for content: StreamSessionManifestContent, completion: ((MediaTrackFrame?) -> Void)?) {
        switch content {
        case .audio:
            return audioContext.readFrame(completion: completion)
        case .video:
            return videoContext.readFrame(completion: completion)
        default:
            break
        }
    }

    func readFrame(for content: StreamSessionManifestContent) -> MediaTrackFrame? {
        switch content {
        case .audio:
            return audioContext.readFrame()
        case .video:
            return videoContext.readFrame()
        default:
            return nil
        }
    }

    func add(_ files: [StreamSegmentFile], for content: StreamSessionManifestContent) {
        switch content {
        case .audio:
            audioContext.add(files)
        case .video:
            videoContext.add(files)
        default:
            break
        }
    }

    func add(_ header: StreamHeaderFile, for content: StreamSessionManifestContent) {
        switch content {
        case .audio:
            audioContext.add(header)
        case .video:
            videoContext.add(header)
        default:
            break
        }
    }

    func clean(for content: StreamSessionManifestContent) {
        switch content {
        case .audio:
            audioContext.clean()
        case .video:
            videoContext.clean()
        default:
            break
        }
    }
}
