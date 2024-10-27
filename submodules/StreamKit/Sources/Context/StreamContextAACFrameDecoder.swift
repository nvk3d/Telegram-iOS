//
//  StreamContextAACFrameDecoder.swift
//  TelegramMediaPlayer
//
//  Created by Nikita Bondar on 18.10.2024.
//

import CoreMedia
import FFMpegBinding

final class StreamContextAACFrameDecoder: StreamContextFrameDecoder {
    // MARK: - Properties

    var errorOccurred: ((Error) -> Void)?

    private let codecContext: FFMpegAVCodecContext
    private let swrContext: FFMpegSWResample

    private let audioFrame: FFMpegAVFrame

    private var resetDecoderOnNextFrame = true

    private let formatDescription: CMAudioFormatDescription

    private var delayedFrames: [MediaTrackFrame] = []

    // MARK: - Init

    init(codecContext: FFMpegAVCodecContext, sampleRate: Int = 44100, channelCount: Int = 2) {
        self.codecContext = codecContext
        self.audioFrame = FFMpegAVFrame()

        self.swrContext = FFMpegSWResample(sourceChannelCount: Int(codecContext.channels()), sourceSampleRate: Int(codecContext.sampleRate()), sourceSampleFormat: codecContext.sampleFormat(), destinationChannelCount: channelCount, destinationSampleRate: sampleRate, destinationSampleFormat: FFMPEG_AV_SAMPLE_FMT_S16)

        var outputDescription = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * channelCount),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var channelLayout = AudioChannelLayout()
        memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono

        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &outputDescription, layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &channelLayout, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription)

        self.formatDescription = formatDescription!
    }

    // MARK: - Interface

    func decode(frame: MediaTrackDecodableFrame) -> MediaTrackFrame? {
        let status = frame.packet.send(toDecoder: codecContext)
        if status == 0 {
            while true {
                let result = self.codecContext.receive(into: audioFrame)
                if case .success = result {
                    if let convertedFrame = convertAudioFrame(audioFrame, pts: frame.pts) {
                        delayedFrames.append(convertedFrame)
                    }
                } else {
                    break
                }
            }

            if delayedFrames.count >= 1 {
                var minFrameIndex = 0
                var minPosition = delayedFrames[0].position
                for i in 1 ..< delayedFrames.count {
                    if CMTimeCompare(delayedFrames[i].position, minPosition) < 0 {
                        minFrameIndex = i
                        minPosition = delayedFrames[i].position
                    }
                }
                return delayedFrames.remove(at: minFrameIndex)
            }
        }

        return nil
    }

    func skip(frames: [MediaTrackDecodableFrame]) {}

    func reset() {
        codecContext.flushBuffers()
    }

    // MARK: - Private. Help

    private func convertAudioFrame(_ frame: FFMpegAVFrame, pts: CMTime) -> MediaTrackFrame? {
        guard let data = self.swrContext.resample(frame) else { return nil }

        var blockBuffer: CMBlockBuffer?

        let bytes = malloc(data.count)!
        data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: data.count)
        let status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: bytes, blockLength: data.count, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &blockBuffer)
        if status != noErr {
            return nil
        }

        var sampleBuffer: CMSampleBuffer?

        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: blockBuffer!, formatDescription: self.formatDescription, sampleCount: Int(data.count / 2), presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &sampleBuffer) == noErr else {
            return nil
        }

        self.resetDecoderOnNextFrame = false

        return MediaTrackFrame(type: .audio, sampleBuffer: sampleBuffer!, decoded: true)
    }
}
