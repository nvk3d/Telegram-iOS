//
//  StreamPlayerContext.swift
//  StreamKit
//
//  Created by Nikita Bondar on 26.10.2024.
//

import CoreMedia
import Foundation

protocol StreamPlayerContext: AnyObject {
    // MARK: - Properties

    var fpsUpdated: ((CMTime) -> Void)? { get set }

    // MARK: - Interface

    func readFrame(for content: StreamSessionManifestContent, completion: ((MediaTrackFrame?) -> Void)?)
    func readFrame(for content: StreamSessionManifestContent) -> MediaTrackFrame?
    func add(_ files: [StreamSegmentFile], for content: StreamSessionManifestContent)
    func add(_ header: StreamHeaderFile, for content: StreamSessionManifestContent)
    func clean(for content: StreamSessionManifestContent)
}
