//
//  StreamContextSingleReader.swift
//  StreamKit
//
//  Created by Nikita Bondar on 26.10.2024.
//

import CoreMedia
import FFMpegBinding

private func readPacketCallback(userData: UnsafeMutableRawPointer?, buffer: UnsafeMutablePointer<UInt8>?, bufferSize: Int32) -> Int32 {
    let context = Unmanaged<StreamContextSingleReader>.fromOpaque(userData!).takeUnretainedValue()
    if let fd = context.files.first?.fd {
        let result = read(fd, buffer, Int(bufferSize))
        if result == 0 {
            return FFMPEG_CONSTANT_AVERROR_EOF
        }
        return Int32(result)
    }
    return FFMPEG_CONSTANT_AVERROR_EOF
}

private func seekCallback(userData: UnsafeMutableRawPointer?, offset: Int64, whence: Int32) -> Int64 {
    let context = Unmanaged<StreamContextSingleReader>.fromOpaque(userData!).takeUnretainedValue()
    if let file = context.files.first {
        if (whence & FFMPEG_AVSEEK_SIZE) != 0 {
            return Int64(file.size)
        } else {
            lseek(file.fd, off_t(offset), SEEK_SET)
            return offset
        }
    }
    return 0
}

final class StreamContextSingleReader {
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

    fileprivate struct File {
        // MARK: - Properties

        let fd: Int32
        let path: String
        let size: Int32
    }

    // MARK: - Properties

    private let headerFile: File?
    fileprivate var files: [File] = []
    private var filesToRead: [StreamSegmentFile] = []

    private var readingError = false
    private var avIoContext: FFMpegAVIOContext?
    private var avFormatContext: FFMpegAVFormatContext?

    private var state: State?
    private var packetQueue: [FFMpegPacket] = []

    // MARK: - Init

    init(headerPath: String) {
        var s = stat()
        stat(headerPath, &s)
        let size = Int32(s.st_size)

        let fd = open(headerPath, O_RDONLY, S_IRUSR)
        if fd >= 0 {
            self.headerFile = File(fd: fd, path: headerPath, size: size)
            self.files.append(headerFile!)
        } else {
            self.headerFile = nil
        }

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
            print("-- ffmpeg not found audio & video: \(headerFile?.path ?? "-")")
            return
        }

        self.state = State(avIoContext: avIoContext, avFormatContext: avFormatContext, audioStream: audioStream, videoStream: videoStream)

        if let videoStream = videoStream {
            avFormatContext.seekFrame(forStreamIndex: Int32(videoStream.index), pts: 0, positionOnKeyframe: true)
        }
    }

    deinit {
        for file in files {
            close(file.fd)
        }
    }

    // MARK: - Interface

    func add(_ files: [StreamSegmentFile]) {
        self.filesToRead.append(contentsOf: files)
//        if self.files.isEmpty {
//            _ = openNextFile()
//        }
    }

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
        let endOfStream = false

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
                //endOfStream = true
                break
            }
        }

        return (frames, endOfStream)
    }
//
//    func seek(timestamp: Double, completed: ((SeekResult, CMTime)?) -> Void) {
//        guard let state = state else { completed(nil); return }
//        packetQueue.removeAll()
//
//        for stream in [state.videoStream, state.audioStream] {
//            if let stream = stream {
//                let pts = CMTimeMakeWithSeconds(timestamp, preferredTimescale: stream.timebase.timescale)
//                state.avFormatContext.seekFrame(forStreamIndex: Int32(stream.index), pts: pts.value, positionOnKeyframe: true)
//                break
//            }
//        }
//
//        state.audioStream?.decoder.reset()
//        state.videoStream?.decoder.reset()
//
//        var audioDescription: SourceDescription?
//        var videoDescription: SourceDescription?
//
//        if let audioStream = state.audioStream {
//            audioDescription = SourceDescription(duration: audioStream.duration, decoder: audioStream.decoder, rotationAngle: 0.0, aspect: 1.0)
//        }
//
//        if let videoStream = state.videoStream {
//            videoDescription = SourceDescription(duration: videoStream.duration, decoder: videoStream.decoder, rotationAngle: videoStream.rotationAngle, aspect: videoStream.aspect)
//        }
//
//        var actualPts: CMTime = CMTimeMake(value: 0, timescale: 1)
//        var extraVideoFrames: [MediaTrackDecodableFrame] = []
//        if timestamp.isZero || state.videoStream == nil {
//            for _ in 0 ..< 24 {
//                guard let packet = readPacketInternal() else { break }
//
//                if let videoStream = state.videoStream, Int(packet.streamIndex) == videoStream.index {
//                    self.packetQueue.append(packet)
//                    let pts = CMTimeMake(value: packet.pts, timescale: videoStream.timebase.timescale)
//                    actualPts = pts
//                    break
//                } else if let audioStream = state.audioStream, Int(packet.streamIndex) == audioStream.index {
//                    self.packetQueue.append(packet)
//                    let pts = CMTimeMake(value: packet.pts, timescale: audioStream.timebase.timescale)
//                    actualPts = pts
//                    break
//                }
//            }
//        } else if let videoStream = state.videoStream {
//            let targetPts = CMTimeMakeWithSeconds(Float64(timestamp), preferredTimescale: videoStream.timebase.timescale)
//            let limitPts = CMTimeMakeWithSeconds(Float64(timestamp + 0.5), preferredTimescale: videoStream.timebase.timescale)
//
//            var audioPackets: [FFMpegPacket] = []
//            while !readingError {
//                guard let packet = readPacket() else { break }
//
//                if let videoStream = state.videoStream, Int(packet.streamIndex) == videoStream.index {
//                    let frame = videoFrameFromPacket(packet, videoStream: videoStream)
//                    extraVideoFrames.append(frame)
//
//                    if CMTimeCompare(frame.dts, limitPts) >= 0 && CMTimeCompare(frame.pts, limitPts) >= 0 {
//                        break
//                    }
//                } else if let audioStream = state.audioStream, Int(packet.streamIndex) == audioStream.index {
//                    audioPackets.append(packet)
//                }
//            }
//
//            if !extraVideoFrames.isEmpty {
//                var closestFrame: MediaTrackDecodableFrame?
//                for frame in extraVideoFrames {
//                    guard CMTimeCompare(frame.pts, targetPts) >= 0 else { continue }
//
//                    if let closestFrameValue = closestFrame {
//                        if CMTimeCompare(frame.pts, closestFrameValue.pts) < 0 {
//                            closestFrame = frame
//                        }
//                    } else {
//                        closestFrame = frame
//                    }
//                }
//                if let closestFrame = closestFrame {
//                    actualPts = closestFrame.pts
//                } else {
//                    if let videoStream = state.videoStream {
//                        actualPts = videoStream.duration
//                    } else {
//                        actualPts = extraVideoFrames.last!.pts
//                    }
//                }
//            }
//
//            if let audioStream = state.audioStream {
//                packetQueue.append(contentsOf: audioPackets.filter({ packet in
//                    let pts = CMTimeMake(value: packet.pts, timescale: audioStream.timebase.timescale)
//                    return CMTimeCompare(pts, actualPts) >= 0
//                }))
//            }
//        }
//
//        completed((SeekResult(audioDescription: audioDescription, videoDescription: videoDescription, extraVideoFrames: extraVideoFrames), actualPts))
//    }

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
        }

        if !files.isEmpty {
            let file = files.removeFirst()
            close(file.fd)
        }

        let opened = openNextFile()
        print("-- file opened: \(opened), files to read: \(filesToRead.count)")
        if state.avFormatContext.readFrame(into: packet) {
            return packet
        } else {
            return nil
        }
    }

    private func openNextFile() -> Bool {
        guard !filesToRead.isEmpty else { return false }

        let segmentFile = filesToRead.removeFirst()

        var s = stat()
        stat(segmentFile.path, &s)
        let size = Int32(s.st_size)

        let fd = open(segmentFile.path, O_RDONLY, S_IRUSR)
        if fd >= 0 {
            let file = File(fd: fd, path: segmentFile.path, size: size)
            files.append(file)
            return true
        }

        return false
    }
}

private func audioFrameFromPacket(_ packet: FFMpegPacket, audioStream: StreamContextSingleReader.StreamContext) -> MediaTrackDecodableFrame {
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

private func videoFrameFromPacket(_ packet: FFMpegPacket, videoStream: StreamContextSingleReader.StreamContext) -> MediaTrackDecodableFrame {
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
