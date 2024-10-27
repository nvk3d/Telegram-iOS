//
//  StreamContextMultipleReader.swift
//  TelegramMediaPlayer
//
//  Created by Nikita Bondar on 15.10.2024.
//

import CoreMedia
import FFMpegBinding

private func readPacketCallback(userData: UnsafeMutableRawPointer?, buffer: UnsafeMutablePointer<UInt8>?, bufferSize: Int32) -> Int32 {
    let context = Unmanaged<StreamContextMultipleReader>.fromOpaque(userData!).takeUnretainedValue()
    if let fd = context.fd {
        let result = read(fd, buffer, Int(bufferSize))
        if result == 0 {
            return FFMPEG_CONSTANT_AVERROR_EOF
        }
        return Int32(result)
    }
    return FFMPEG_CONSTANT_AVERROR_EOF
}

private func seekCallback(userData: UnsafeMutableRawPointer?, offset: Int64, whence: Int32) -> Int64 {
    let context = Unmanaged<StreamContextMultipleReader>.fromOpaque(userData!).takeUnretainedValue()
    if let fd = context.fd {
        if (whence & FFMPEG_AVSEEK_SIZE) != 0 {
            return Int64(context.size)
        } else {
            lseek(fd, off_t(offset), SEEK_SET)
            return offset
        }
    }
    return 0
}

final class StreamContextMultipleReader {
    // MARK: - Children

    struct ContextInfo {
        // MARK: - Properties

        let audioStream: StreamContextInfo?
        let videoStream: StreamContextInfo?
    }

    struct SeekResult {
        // MARK: - Properties

        let audioDescription: SourceDescription?
        let videoDescription: SourceDescription?
        let extraVideoFrames: [MediaTrackDecodableFrame]
    }

    struct SourceDescription {
        // MARK: - Properties

        let duration: CMTime
        let decoder: StreamContextFrameDecoder
        let rotationAngle: Double
        let aspect: Double
    }

    struct StreamContextInfo {
        // MARK: - Properties

        let duration: CMTime
        let decoder: StreamContextFrameDecoder
        let fps: CMTime
    }

    private struct State {
        // MARK: - Properties

        let avIoContext: FFMpegAVIOContext
        let avFormatContext: FFMpegAVFormatContext

        let audioStream: StreamContext?
        let videoStream: StreamContext?
    }

    fileprivate struct StreamContext {
        // MARK: - Properties

        let index: Int
        let codecContext: FFMpegAVCodecContext?
        let fps: CMTime
        let timebase: CMTime
        let duration: CMTime
        let decoder: StreamContextFrameDecoder
        let rotationAngle: Double
        let aspect: Double
    }

    // MARK: - Properties

    private let path: String

    fileprivate let fd: Int32?
    fileprivate let size: Int32

    private var readingError = false
    private var avIoContext: FFMpegAVIOContext?
    private var avFormatContext: FFMpegAVFormatContext?

    private var state: State?
    private var packetQueue: [FFMpegPacket] = []

    // MARK: - Init

    init(path: String) {
        var s = stat()
        stat(path, &s)
        self.size = Int32(s.st_size)

        let fd = open(path, O_RDONLY, S_IRUSR)
        if fd >= 0 {
            self.fd = fd
        } else {
            self.fd = nil
        }

        self.path = path

        let avFormatContext = FFMpegAVFormatContext()
        let ioBufferSize = 64 * 1024

        guard let avIoContext = FFMpegAVIOContext(
            bufferSize: Int32(ioBufferSize),
            opaqueContext: Unmanaged.passUnretained(self).toOpaque(),
            readPacket: readPacketCallback,
            writePacket: nil,
            seek: seekCallback,
            isSeekable: true
        ) else {
            self.readingError = true
            return
        }
        self.avIoContext = avIoContext

        avFormatContext.setIO(avIoContext)

        if !avFormatContext.openInput() {
            readingError = true
            return
        }

        if !avFormatContext.findStreamInfo() {
            readingError = true
            return
        }

        self.avFormatContext = avFormatContext

        var audioStream: StreamContext?
        var videoStream: StreamContext?

        for streamIndexNumber in avFormatContext.streamIndices(for: FFMpegAVFormatStreamTypeAudio) {
            let streamIndex = streamIndexNumber.int32Value
            let codecId = avFormatContext.codecId(atStreamIndex: streamIndex)

            var codec: FFMpegAVCodec?

            if codec == nil {
                codec = FFMpegAVCodec.find(forId: codecId)
            }

            if let codec = codec {
                let codecContext = FFMpegAVCodecContext(codec: codec)
                if avFormatContext.codecParams(atStreamIndex: streamIndex, to: codecContext) {
                    if codecContext.open() {
                        let fpsAndTimebase = avFormatContext.fpsAndTimebase(forStreamIndex: streamIndex, defaultTimeBase: CMTimeMake(value: 1, timescale: 40000))
                        let (fps, timebase) = (fpsAndTimebase.fps, fpsAndTimebase.timebase)

                        let duration = CMTimeMake(value: avFormatContext.duration(atStreamIndex: streamIndex), timescale: timebase.timescale)
                        audioStream = StreamContext(index: Int(streamIndex), codecContext: codecContext, fps: fps, timebase: timebase, duration: duration, decoder: StreamContextAACFrameDecoder(codecContext: codecContext), rotationAngle: 0.0, aspect: 1.0)
                        break
                    }
                }
            }
        }

        for streamIndexNumber in avFormatContext.streamIndices(for: FFMpegAVFormatStreamTypeVideo) {
            let streamIndex = streamIndexNumber.int32Value
            if avFormatContext.isAttachedPic(atStreamIndex: streamIndex) {
                continue
            }

            let codecId = avFormatContext.codecId(atStreamIndex: streamIndex)

            let fpsAndTimebase = avFormatContext.fpsAndTimebase(forStreamIndex: streamIndex, defaultTimeBase: CMTimeMake(value: 1, timescale: 40000))
            let (fps, timebase) = (fpsAndTimebase.fps, fpsAndTimebase.timebase)

            let duration = CMTimeMake(value: avFormatContext.duration(atStreamIndex: streamIndex), timescale: timebase.timescale)

            let metrics = avFormatContext.metricsForStream(at: streamIndex)

            let rotationAngle: Double = metrics.rotationAngle
            let aspect = Double(metrics.width) / Double(metrics.height)

            if codecId == FFMpegCodecIdH264 {
                videoStream = StreamContext(index: Int(streamIndex), codecContext: nil, fps: fps, timebase: timebase, duration: duration, decoder: StreamContextH264FrameDecoder(), rotationAngle: rotationAngle, aspect: aspect)
            } else {
                assertionFailure("unknown video codec type")
            }
        }

        if audioStream == nil, videoStream == nil {
            self.readingError = true
            print("-- ffmpeg not found audio & video: \(path)")
            return
        }

        self.state = State(avIoContext: avIoContext, avFormatContext: avFormatContext, audioStream: audioStream, videoStream: videoStream)

        if let videoStream = videoStream {
            avFormatContext.seekFrame(forStreamIndex: Int32(videoStream.index), pts: 0, positionOnKeyframe: true)
        }
    }

    deinit {
        if let fd = fd {
            close(fd)
        }
    }

    // MARK: - Interface

    func contextInfo() -> ContextInfo? {
        if let state = state {
            var audioStreamContext: StreamContextInfo?
            var videoStreamContext: StreamContextInfo?

            if let audioStream = state.audioStream {
                audioStreamContext = StreamContextInfo(duration: audioStream.duration, decoder: audioStream.decoder, fps: audioStream.fps)
            }

            if let videoStream = state.videoStream {
                videoStreamContext = StreamContextInfo(duration: videoStream.duration, decoder: videoStream.decoder, fps: videoStream.fps)
            }

            return ContextInfo(audioStream: audioStreamContext, videoStream: videoStreamContext)
        }
        return nil
    }

    func readFrames(count: Int) -> (frames: [MediaTrackDecodableFrame], endOfStream: Bool) {
        if readingError {
            return ([], true)
        }

        guard let state = state else { return ([], true) }

        var frames: [MediaTrackDecodableFrame] = []
        var endOfStream = false

        while !readingError, frames.count < count {
            if let packet = readPacket() {
                if let videoStream = state.videoStream, videoStream.index == Int(packet.streamIndex) {
                    let frame = videoFrameFromPacket(packet, videoStream: videoStream)
                    if frame.pts.seconds < 0.0 {
                        break
                    }
                    frames.append(frame)
                } else if let audioStream = state.audioStream, audioStream.index == Int(packet.streamIndex) {
                    let frame = audioFrameFromPacket(packet, audioStream: audioStream)
                    if frame.pts.seconds < 0.0 {
                        break
                    }
                    frames.append(frame)
                }
            } else {
                endOfStream = true
                break
            }
        }

        return (frames, endOfStream)
    }

    // MARK: - Private. Help

    private func readPacket() -> FFMpegPacket? {
        if !packetQueue.isEmpty {
            return packetQueue.remove(at: 0)
        } else {
            return readPacketInternal()
        }
    }

    private func readPacketInternal() -> FFMpegPacket? {
        guard let state = state else { return nil }

        let packet = FFMpegPacket()
        if state.avFormatContext.readFrame(into: packet) {
            return packet
        } else {
            return nil
        }
    }
}

private func audioFrameFromPacket(_ packet: FFMpegPacket, audioStream: StreamContextMultipleReader.StreamContext) -> MediaTrackDecodableFrame {
    let packetPts = packet.pts

    let pts = CMTimeMake(value: packetPts, timescale: audioStream.timebase.timescale)
    let dts = CMTimeMake(value: packet.dts, timescale: audioStream.timebase.timescale)

    let duration: CMTime

    let frameDuration = packet.duration
    if frameDuration != 0 {
        duration = CMTimeMake(value: frameDuration * audioStream.timebase.value, timescale: audioStream.timebase.timescale)
    } else {
        duration = audioStream.fps
    }

    return MediaTrackDecodableFrame(type: .audio, packet: packet, pts: pts, dts: dts, duration: duration)
}

private func videoFrameFromPacket(_ packet: FFMpegPacket, videoStream: StreamContextMultipleReader.StreamContext) -> MediaTrackDecodableFrame {
    let packetPts = packet.pts

    let pts = CMTimeMake(value: packetPts, timescale: videoStream.timebase.timescale)
    let dts = CMTimeMake(value: packet.dts, timescale: videoStream.timebase.timescale)

    let duration: CMTime

    let frameDuration = packet.duration
    if frameDuration != 0 {
        duration = CMTimeMake(value: frameDuration * videoStream.timebase.value, timescale: videoStream.timebase.timescale)
    } else {
        duration = CMTimeMake(value: Int64(videoStream.fps.timescale), timescale: Int32(videoStream.fps.value))
    }

    return MediaTrackDecodableFrame(type: .video, packet: packet, pts: pts, dts: dts, duration: duration)
}
