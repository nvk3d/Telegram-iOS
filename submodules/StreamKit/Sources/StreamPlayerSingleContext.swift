//
//  StreamPlayerSingleContext.swift
//  StreamKit
//
//  Created by Nikita Bondar on 26.10.2024.
//

import CoreMedia
import Foundation
import SwiftSignalKit

final class StreamPlayerSingleContext: StreamPlayerContext {
    // MARK: - Properties

    var fpsUpdated: ((CMTime) -> Void)?

    private let context: StreamContext

    // MARK: - Init

    init() {
        context = StreamSingleContext(gopCount: 30, queue: Queue())
        context.fpsUpdated = { [weak self] fps in
            guard let self else { return }
            self.fpsUpdated?(fps)
        }
    }

    // MARK: - Interface

    func readFrame(for content: StreamSessionManifestContent, completion: ((MediaTrackFrame?) -> Void)?) {
        context.readFrame(completion: completion)
    }

    func readFrame(for content: StreamSessionManifestContent) -> MediaTrackFrame? {
        context.readFrame()
    }

    func add(_ files: [StreamSegmentFile], for content: StreamSessionManifestContent) {
        context.add(files)
    }

    func add(_ header: StreamHeaderFile, for content: StreamSessionManifestContent) {
        context.add(header)
    }

    func clean(for content: StreamSessionManifestContent) {
        context.clean()
    }
}
