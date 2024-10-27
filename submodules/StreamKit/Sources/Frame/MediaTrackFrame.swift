//
//  TrackFrame.swift
//  FFmpegApp
//
//  Created by Nikita Bondar on 04.03.2024.
//

import CoreMedia
import Foundation

enum MediaTrackFrameResult {
    // MARK: - Cases

    case noFrames
    case skipFrame
    case frame(MediaTrackFrame)
    case finished
}

final class MediaTrackFrame {
    // MARK: - Properties

    let type: MediaTrackFrameType
    let sampleBuffer: CMSampleBuffer
    let decoded: Bool
    let rotationAngle: Double

    var position: CMTime {
        CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    }

    var duration: CMTime {
        CMSampleBufferGetDuration(sampleBuffer)
    }

    // MARK: - Init

    init(type: MediaTrackFrameType, sampleBuffer: CMSampleBuffer, decoded: Bool, rotationAngle: Double = 0.0) {
        self.type = type
        self.sampleBuffer = sampleBuffer
        self.decoded = decoded
        self.rotationAngle = rotationAngle
    }
}
