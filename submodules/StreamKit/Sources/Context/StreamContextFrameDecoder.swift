//
//  StreamContextFrameDecoder.swift
//  TelegramMediaPlayer
//
//  Created by Nikita Bondar on 16.10.2024.
//

import Foundation

protocol StreamContextFrameDecoder: AnyObject {
    // MARK: - Properties

    var errorOccurred: ((Error) -> Void)? { get set }

    // MARK: - Interface

    func decode(frame: MediaTrackDecodableFrame) -> MediaTrackFrame?
    func reset()
}
