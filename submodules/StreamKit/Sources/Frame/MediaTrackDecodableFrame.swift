//
//  TrackDecodableFrame.swift
//  FFmpegApp
//
//  Created by Nikita Bondar on 04.03.2024.
//

import CoreMedia
import FFMpegBinding

enum MediaTrackFrameType {
    // MARK: - Cases

    case audio
    case video
}

final class MediaTrackDecodableFrame {
    // MARK: - Properties

    public let type: MediaTrackFrameType
    public let packet: FFMpegPacket
    public let pts: CMTime
    public let dts: CMTime
    public let duration: CMTime

    // MARK: - Init

    init(type: MediaTrackFrameType, packet: FFMpegPacket, pts: CMTime, dts: CMTime, duration: CMTime) {
        self.type = type
        
        self.pts = pts
        self.dts = dts
        self.duration = duration

        self.packet = packet
    }

    func copyPacketData() -> Data {
        Data(bytes: packet.data, count: Int(packet.size))
    }
}
