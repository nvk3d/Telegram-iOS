//
//  StreamContext.swift
//  TelegramMediaPlayer
//
//  Created by Nikita Bondar on 15.10.2024.
//

import CoreMedia
import SwiftSignalKit

protocol StreamContext: AnyObject {
    // MARK: - Properties

    var fpsUpdated: ((CMTime) -> Void)? { get set }

    // MARK: - Interface

    func readFrame(completion: ((MediaTrackFrame?) -> Void)?)
    func readFrame() -> MediaTrackFrame?
    func add(_ files: [StreamSegmentFile])
    func add(_ header: StreamHeaderFile)
    func clean()
}
