//
//  StreamAudioRenderer.swift
//  StreamKit
//
//  Created by Nikita Bondar on 19.10.2024.
//

import AVFoundation
import CoreMedia
import SwiftSignalKit

private let audioPlayerRendererBufferContextMap = Atomic<[Int32: Atomic<AudioPlayerRendererBufferContext>]>(value: [:])
//private let audioPlayerRendererQueue = Queue()

private var _nextPlayerRendererBufferContextId: Int32 = 1
private func registerPlayerRendererBufferContext(_ context: Atomic<AudioPlayerRendererBufferContext>) -> Int32 {
    var id: Int32 = 0

    let _ = audioPlayerRendererBufferContextMap.modify { contextMap in
        id = _nextPlayerRendererBufferContextId
        _nextPlayerRendererBufferContextId += 1

        var contextMap = contextMap
        contextMap[id] = context
        return contextMap
    }
    return id
}

private func unregisterPlayerRendererBufferContext(_ id: Int32) {
    let _ = audioPlayerRendererBufferContextMap.modify { contextMap in
        var contextMap = contextMap
        let _ = contextMap.removeValue(forKey: id)
        return contextMap
    }
}

private func withPlayerRendererBuffer(_ id: Int32, _ f: (Atomic<AudioPlayerRendererBufferContext>) -> Void) {
    audioPlayerRendererBufferContextMap.with { contextMap in
        if let context = contextMap[id] {
            f(context)
        }
    }
}

private let kOutputBus: UInt32 = 0
private let kInputBus: UInt32 = 1

private func rendererInputProc(refCon: UnsafeMutableRawPointer, ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, inTimeStamp: UnsafePointer<AudioTimeStamp>, inBusNumber: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    guard let ioData = ioData else {
        return noErr
    }

    let bufferList = UnsafeMutableAudioBufferListPointer(ioData)

    var rendererFillOffset = (0, 0)
    var notifyLowWater: (() -> Void)?
    var updatedRate: (() -> Void)?

    withPlayerRendererBuffer(Int32(intptr_t(bitPattern: refCon)), { context in
        context.with { context in
            switch context.state {
            case let .playing(rate, didSetRate):
                if context.buffer.availableBytes != 0 {
                    let sampleIndex = context.bufferMaxChannelSampleIndex - Int64(context.buffer.availableBytes / (2 * 2))

                    if !didSetRate {
                        context.state = .playing(rate: rate, didSetRate: true)
                        let masterClock = CMTimebaseCopySource(context.timebase)
                        CMTimebaseSetRateAndAnchorTime(context.timebase, rate: rate, anchorTime: CMTimeMake(value: sampleIndex, timescale: 44100), immediateSourceTime: CMSyncGetTime(masterClock))
                        updatedRate = context.updatedRate
                    } else {
                        context.renderTimestampTick += 1
                        if context.renderTimestampTick % 1000 == 0 {
                            let delta = (Double(sampleIndex) / 44100.0) - CMTimeGetSeconds(CMTimebaseGetTime(context.timebase))
                            if delta > 0.01 {
                                CMTimebaseSetTime(context.timebase, time: CMTimeMake(value: sampleIndex, timescale: 44100))
                                updatedRate = context.updatedRate
                            }
                        }
                    }

                    let rendererBuffer = context.buffer

                    while rendererFillOffset.0 < bufferList.count {
                        if let bufferData = bufferList[rendererFillOffset.0].mData {
                            let bufferDataSize = Int(bufferList[rendererFillOffset.0].mDataByteSize)

                            let dataOffset = rendererFillOffset.1
                            if dataOffset == bufferDataSize {
                                rendererFillOffset = (rendererFillOffset.0 + 1, 0)
                                continue
                            }

                            let consumeCount = bufferDataSize - dataOffset

                            let actualConsumedCount = rendererBuffer.dequeue(bufferData.advanced(by: dataOffset), count: consumeCount)

                            var samplePtr = bufferData.advanced(by: dataOffset).assumingMemoryBound(to: Int16.self)
                            for _ in 0 ..< actualConsumedCount / 4 {
                                var sample: Int16 = samplePtr.pointee
                                if sample < 0 {
                                    if sample <= -32768 {
                                        sample = Int16.max
                                    } else {
                                        sample = -sample
                                    }
                                }
                                samplePtr = samplePtr.advanced(by: 2)

                                if context.audioLevelPeak < sample {
                                    context.audioLevelPeak = sample
                                }
                                context.audioLevelPeakCount += 1

                                if context.audioLevelPeakCount >= 1200 {
                                    let level = Float(context.audioLevelPeak) / (4000.0)
                                    context.updatedLevel(level)
                                    context.audioLevelPeak = 0
                                    context.audioLevelPeakCount = 0
                                }
                            }

                            rendererFillOffset.1 += actualConsumedCount

                            if actualConsumedCount == 0 {
                                break
                            }
                        } else {
                            break
                        }
                    }
                }

                if !context.notifiedLowWater {
                    let availableBytes = context.buffer.availableBytes
                    if availableBytes <= context.lowWaterSize {
                        context.notifiedLowWater = true
                        notifyLowWater = context.notifyLowWater
                    }
                }
            case .paused:
                break
            }
        }
    })

    for i in rendererFillOffset.0 ..< bufferList.count {
        var dataOffset = 0
        if i == rendererFillOffset.0 {
            dataOffset = rendererFillOffset.1
        }
        if let data = bufferList[i].mData {
            memset(data.advanced(by: dataOffset), 0, Int(bufferList[i].mDataByteSize) - dataOffset)
        }
    }

    if let notifyLowWater = notifyLowWater {
        notifyLowWater()
    }

    if let updatedRate = updatedRate {
        updatedRate()
    }

    return noErr
}

private enum AudioPlayerRendererState {
    // MARK: - Cases

    case paused
    case playing(rate: Double, didSetRate: Bool)
}

private final class AudioPlayerRendererBufferContext {
    // MARK: - Properties

    var state: AudioPlayerRendererState = .paused
    let timebase: CMTimebase
    let buffer: RingByteBuffer
    var audioLevelPeak: Int16 = 0
    var audioLevelPeakCount: Int = 0
    var audioLevelPeakUpdate: Double = 0.0
    var bufferMaxChannelSampleIndex: Int64 = 0
    var lowWaterSize: Int
    var notifyLowWater: () -> Void
    var updatedRate: () -> Void
    var updatedLevel: (Float) -> Void
    var notifiedLowWater = false
    var overflowData = Data()
    var overflowDataMaxChannelSampleIndex: Int64 = 0
    var renderTimestampTick: Int64 = 0

    init(timebase: CMTimebase, buffer: RingByteBuffer, lowWaterSize: Int, notifyLowWater: @escaping () -> Void, updatedRate: @escaping () -> Void, updatedLevel: @escaping (Float) -> Void) {
        self.timebase = timebase
        self.buffer = buffer
        self.lowWaterSize = lowWaterSize
        self.notifyLowWater = notifyLowWater
        self.updatedRate = updatedRate
        self.updatedLevel = updatedLevel
    }
}

private struct RequestingFramesContext {
    // MARK: - Properties

    let queue: DispatchQueue
    let takeFrame: () -> MediaTrackFrameResult
}

private final class AudioPlayerRendererContext {
    // MARK: - Properties

    let audioStreamDescription: AudioStreamBasicDescription
    let audioPlayerRendererQueue: Queue
    let bufferSizeInSeconds: Int = 5
    let lowWaterSizeInSeconds: Int = 2

    let controlTimebase: CMTimebase
    let updatedRate: () -> Void
    let audioPaused: () -> Void

    var audioGraph: AUGraph?
    var timePitchAudioUnit: AudioComponentInstance?
    var mixerAudioUnit: AudioComponentInstance?
    var equalizerAudioUnit: AudioComponentInstance?
    var outputAudioUnit: AudioComponentInstance?

    var bufferContextId: Int32!
    let bufferContext: Atomic<AudioPlayerRendererBufferContext>

    var requestingFramesContext: RequestingFramesContext?

    var baseRate: Double
    var paused = false
    var soundMuted: Bool

    var volume: Double = 1.0

    // MARK: - Init

    init(controlTimebase: CMTimebase, baseRate: Double, soundMuted: Bool, queue: Queue, updatedRate: @escaping () -> Void, audioPaused: @escaping () -> Void) {
        self.audioPlayerRendererQueue = queue
        assert(audioPlayerRendererQueue.isCurrent())

        self.controlTimebase = controlTimebase
        self.updatedRate = updatedRate
        self.audioPaused = audioPaused

        self.baseRate = baseRate
        self.soundMuted = soundMuted

        self.audioStreamDescription = audioRendererNativeStreamDescription()

        let bufferSize = Int(audioStreamDescription.mSampleRate) * bufferSizeInSeconds * Int(audioStreamDescription.mBytesPerFrame)
        let lowWaterSize = Int(audioStreamDescription.mSampleRate) * lowWaterSizeInSeconds * Int(audioStreamDescription.mBytesPerFrame)

        var notifyLowWater: () -> Void = { }

        self.bufferContext = Atomic(value: AudioPlayerRendererBufferContext(timebase: controlTimebase, buffer: RingByteBuffer(size: bufferSize), lowWaterSize: lowWaterSize, notifyLowWater: {
            notifyLowWater()
        }, updatedRate: {
            updatedRate()
        }, updatedLevel: { _ in

        }))
        self.bufferContextId = registerPlayerRendererBufferContext(self.bufferContext)

        notifyLowWater = { [weak self] in
            guard let self else { return }
            self.audioPlayerRendererQueue.async { self.checkBuffer() }
        }
    }

    deinit {
        assert(audioPlayerRendererQueue.isCurrent())

        unregisterPlayerRendererBufferContext(bufferContextId)
        closeAudioUnit()
    }

    // MARK: - Interface

    func start() {
        assert(audioPlayerRendererQueue.isCurrent())

        if paused {
            paused = false
            audioSessionAcquired()
        }
    }

    func stop() {
        assert(audioPlayerRendererQueue.isCurrent())

        if !paused {
            paused = true
            setRate(0.0)
            closeAudioUnit()
        }
    }

    func beginRequestingFrames(queue: DispatchQueue, takeFrame: @escaping () -> MediaTrackFrameResult) {
        requestingFramesContext = RequestingFramesContext(queue: queue, takeFrame: takeFrame)
        checkBuffer()
    }

    func endRequestingFrames() {
        requestingFramesContext = nil
    }

    func flushBuffers(at timestamp: CMTime, completion: () -> Void) {
        assert(audioPlayerRendererQueue.isCurrent())

        bufferContext.with { context in
            context.buffer.clear()
            context.bufferMaxChannelSampleIndex = 0
            context.notifiedLowWater = false
            context.overflowData = Data()
            context.overflowDataMaxChannelSampleIndex = 0
            CMTimebaseSetTime(context.timebase, time: timestamp)

            switch context.state {
            case let .playing(rate, _):
                context.state = .playing(rate: rate, didSetRate: false)
            case .paused:
                break
            }
        }

        completion()
    }

    func setBaseRate(_ baseRate: Double) {
        if let timePitchAudioUnit = timePitchAudioUnit, !self.baseRate.isEqual(to: baseRate) {
            self.baseRate = baseRate
            AudioUnitSetParameter(timePitchAudioUnit, kTimePitchParam_Rate, kAudioUnitScope_Global, 0, Float32(baseRate), 0)
            bufferContext.with { context in
                if case .playing = context.state {
                    context.state = .playing(rate: baseRate, didSetRate: false)
                }
            }
        }
    }

    func setRate(_ rate: Double) {
        assert(audioPlayerRendererQueue.isCurrent())

        if !rate.isZero && paused {
            start()
        }

        let baseRate = baseRate

        bufferContext.with { context in
            if !rate.isZero {
                if case .playing = context.state {
                } else {
                    context.state = .playing(rate: baseRate, didSetRate: false)
                }
            } else {
                context.state = .paused
                CMTimebaseSetRate(context.timebase, rate: 0.0)
            }
        }
    }

    func setVolume(_ volume: Double) {
        self.volume = volume

        if let mixerAudioUnit = mixerAudioUnit {
            AudioUnitSetParameter(mixerAudioUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, Float32(volume) * (soundMuted ? 0.0 : 1.0), 0)
        }
    }

    func setSoundMuted(soundMuted: Bool) {
        self.soundMuted = soundMuted

        if let mixerAudioUnit = mixerAudioUnit {
            AudioUnitSetParameter(mixerAudioUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, Float32(volume) * (soundMuted ? 0.0 : 1.0), 0)
        }
    }

    // MARK: - Private. Help

    private func audioSessionAcquired() {
        assert(audioPlayerRendererQueue.isCurrent())

        startAudioUnit()

        if let audioGraph = audioGraph {
            guard AUGraphStart(audioGraph) == noErr else {
                closeAudioUnit()
                return
            }
        }
    }

    private func checkBuffer() {
        assert(audioPlayerRendererQueue.isCurrent())

        while true {
            let bytesToRequest = bufferContext.with { context -> Int in
                let availableBytes = context.buffer.availableBytes
                if availableBytes <= context.lowWaterSize {
                    return context.buffer.size - availableBytes
                } else {
                    return 0
                }
            }

            if bytesToRequest == 0 {
                bufferContext.with { context in
                    context.notifiedLowWater = false
                }
                break
            }

            let overflowTakenLength = bufferContext.with { context -> Int in
                let takeLength = min(context.overflowData.count, bytesToRequest)
                if takeLength != 0 {
                    if takeLength == context.overflowData.count {
                        let data = context.overflowData
                        context.overflowData = Data()
                        enqueueSamples(data, sampleIndex: context.overflowDataMaxChannelSampleIndex - Int64(data.count / (2 * 2)))
                    } else {
                        let data = context.overflowData.subdata(in: 0 ..< takeLength)
                        enqueueSamples(data, sampleIndex: context.overflowDataMaxChannelSampleIndex - Int64(context.overflowData.count / (2 * 2)))
                        context.overflowData.replaceSubrange(0 ..< takeLength, with: Data())
                    }
                }
                return takeLength
            }

            if overflowTakenLength != 0 {
                continue
            }

            if let requestingFramesContext = requestingFramesContext {
                requestingFramesContext.queue.async { [weak self] in
                    guard let self else { return }

                    let takenFrame = requestingFramesContext.takeFrame()
                    self.audioPlayerRendererQueue.async { [weak self] in
                        guard let self = self else { return }

                        switch takenFrame {
                        case let .frame(frame):
                            if let dataBuffer = CMSampleBufferGetDataBuffer(frame.sampleBuffer) {
                                let dataLength = CMBlockBufferGetDataLength(dataBuffer)
                                let takeLength = min(dataLength, bytesToRequest)

                                let pts = CMSampleBufferGetPresentationTimeStamp(frame.sampleBuffer)
                                let bufferSampleIndex = CMTimeConvertScale(pts, timescale: 44100, method: .roundAwayFromZero).value

                                let bytes = malloc(takeLength)!
                                CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: takeLength, destination: bytes)
                                self.enqueueSamples(Data(bytesNoCopy: bytes.assumingMemoryBound(to: UInt8.self), count: takeLength, deallocator: .free), sampleIndex: bufferSampleIndex)

                                if takeLength < dataLength {
                                    self.bufferContext.with { context in
                                        let copyOffset = context.overflowData.count
                                        context.overflowData.count += dataLength - takeLength
                                        context.overflowData.withUnsafeMutableBytes { buffer -> Void in
                                            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                                                return
                                            }
                                            CMBlockBufferCopyDataBytes(dataBuffer, atOffset: takeLength, dataLength: dataLength - takeLength, destination: bytes.advanced(by: copyOffset))
                                        }
                                    }
                                }

                                self.audioPlayerRendererQueue.after(max(0.0, frame.duration.seconds - 0.01) / self.baseRate) { [weak self] in
                                    guard let self else { return }
                                    self.checkBuffer()
                                }
                            } else {
                                assertionFailure()
                            }
                        case .skipFrame:
                            self.audioPlayerRendererQueue.after(0.001) { [weak self] in
                                guard let self else { return }
                                self.checkBuffer()
                            }
                            break
                        case .noFrames, .finished:
                            self.requestingFramesContext = nil
                        }
                    }
                }
            } else {
                bufferContext.with { context in
                    context.notifiedLowWater = false
                }
            }

            break
        }
    }

    private func enqueueSamples(_ data: Data, sampleIndex: Int64) {
        assert(audioPlayerRendererQueue.isCurrent())

        bufferContext.with { context in
            let bytesToCopy = min(context.buffer.size - context.buffer.availableBytes, data.count)
            data.withUnsafeBytes { buffer -> Void in
                guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                let _ = context.buffer.enqueue(UnsafeRawPointer(bytes), count: bytesToCopy)
                context.bufferMaxChannelSampleIndex = sampleIndex + Int64(data.count / (2 * 2))
            }
        }
    }

    private func startAudioUnit() {
        assert(audioPlayerRendererQueue.isCurrent())

        guard audioGraph == nil else { return }

        var maybeAudioGraph: AUGraph?
        guard NewAUGraph(&maybeAudioGraph) == noErr, let audioGraph = maybeAudioGraph else {
            return
        }

        var converterNode: AUNode = 0
        var converterDescription = AudioComponentDescription()
        converterDescription.componentType = kAudioUnitType_FormatConverter
        converterDescription.componentSubType = kAudioUnitSubType_AUConverter
        converterDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        guard AUGraphAddNode(audioGraph, &converterDescription, &converterNode) == noErr else {
            return
        }

        var timePitchNode: AUNode = 0
        var timePitchDescription = AudioComponentDescription()
        timePitchDescription.componentType = kAudioUnitType_FormatConverter
        timePitchDescription.componentSubType = kAudioUnitSubType_AUiPodTimeOther
        timePitchDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        guard AUGraphAddNode(audioGraph, &timePitchDescription, &timePitchNode) == noErr else {
            return
        }

        var mixerNode: AUNode = 0
        var mixerDescription = AudioComponentDescription()
        mixerDescription.componentType = kAudioUnitType_Mixer
        mixerDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer
        mixerDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        guard AUGraphAddNode(audioGraph, &mixerDescription, &mixerNode) == noErr else {
            return
        }

        var equalizerNode: AUNode = 0
        var equalizerDescription = AudioComponentDescription()
        equalizerDescription.componentType = kAudioUnitType_Effect
        equalizerDescription.componentSubType = kAudioUnitSubType_NBandEQ
        equalizerDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        guard AUGraphAddNode(audioGraph, &equalizerDescription, &equalizerNode) == noErr else {
            return
        }

        var outputNode: AUNode = 0
        var outputDesc = AudioComponentDescription()
        outputDesc.componentType = kAudioUnitType_Output
        outputDesc.componentSubType = kAudioUnitSubType_RemoteIO
        outputDesc.componentFlags = 0
        outputDesc.componentFlagsMask = 0
        outputDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        guard AUGraphAddNode(audioGraph, &outputDesc, &outputNode) == noErr else {
            return
        }

        guard AUGraphOpen(audioGraph) == noErr else {
            return
        }

        guard AUGraphConnectNodeInput(audioGraph, converterNode, 0, timePitchNode, 0) == noErr else {
            return
        }

        guard AUGraphConnectNodeInput(audioGraph, timePitchNode, 0, mixerNode, 0) == noErr else {
            return
        }

        guard AUGraphConnectNodeInput(audioGraph, mixerNode, 0, equalizerNode, 0) == noErr else {
            return
        }

        guard AUGraphConnectNodeInput(audioGraph, equalizerNode, 0, outputNode, 0) == noErr else {
            return
        }

        var maybeConverterAudioUnit: AudioComponentInstance?
        guard AUGraphNodeInfo(audioGraph, converterNode, &converterDescription, &maybeConverterAudioUnit) == noErr, let converterAudioUnit = maybeConverterAudioUnit else {
            return
        }

        var maybeTimePitchAudioUnit: AudioComponentInstance?
        guard AUGraphNodeInfo(audioGraph, timePitchNode, &timePitchDescription, &maybeTimePitchAudioUnit) == noErr, let timePitchAudioUnit = maybeTimePitchAudioUnit else {
            return
        }
        AudioUnitSetParameter(timePitchAudioUnit, kTimePitchParam_Rate, kAudioUnitScope_Global, 0, Float32(baseRate), 0)

        var maybeMixerAudioUnit: AudioComponentInstance?
        guard AUGraphNodeInfo(audioGraph, mixerNode, &mixerDescription, &maybeMixerAudioUnit) == noErr, let mixerAudioUnit = maybeMixerAudioUnit else {
            return
        }

        var maybeEqualizerAudioUnit: AudioComponentInstance?
        guard AUGraphNodeInfo(audioGraph, equalizerNode, &equalizerDescription, &maybeEqualizerAudioUnit) == noErr, let equalizerAudioUnit = maybeEqualizerAudioUnit else {
            return
        }

        AudioUnitSetParameter(equalizerAudioUnit, kAUNBandEQParam_GlobalGain, kAudioUnitScope_Global, 0, 12.0, 0)

        var maybeOutputAudioUnit: AudioComponentInstance?
        guard AUGraphNodeInfo(audioGraph, outputNode, &outputDesc, &maybeOutputAudioUnit) == noErr, let outputAudioUnit = maybeOutputAudioUnit else {
            return
        }

        var outputAudioFormat = audioRendererNativeStreamDescription()

        AudioUnitSetProperty(converterAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outputAudioFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        var streamFormat = AudioStreamBasicDescription()
        AudioUnitSetProperty(converterAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitSetProperty(timePitchAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitSetProperty(mixerAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitSetProperty(equalizerAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        var callbackStruct = AURenderCallbackStruct()
        callbackStruct.inputProc = rendererInputProc
        callbackStruct.inputProcRefCon = UnsafeMutableRawPointer(bitPattern: intptr_t(bufferContextId))

        guard AUGraphSetNodeInputCallback(audioGraph, converterNode, 0, &callbackStruct) == noErr else {
            return
        }

        var one: UInt32 = 1
        guard AudioUnitSetProperty(outputAudioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, kOutputBus, &one, 4) == noErr else {
            return
        }

        var maximumFramesPerSlice: UInt32 = 4096
        AudioUnitSetProperty(converterAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, 4)
        AudioUnitSetProperty(timePitchAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, 4)
        AudioUnitSetProperty(mixerAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, 4)
        AudioUnitSetProperty(equalizerAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, 4)
        AudioUnitSetProperty(outputAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, 4)

        AudioUnitSetParameter(mixerAudioUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, Float32(volume) * (soundMuted ? 0.0 : 1.0), 0)

        guard AUGraphInitialize(audioGraph) == noErr else {
            return
        }

        self.audioGraph = audioGraph
        self.timePitchAudioUnit = timePitchAudioUnit
        self.mixerAudioUnit = mixerAudioUnit
        self.equalizerAudioUnit = equalizerAudioUnit
        self.outputAudioUnit = outputAudioUnit
    }

    private func closeAudioUnit() {
        assert(audioPlayerRendererQueue.isCurrent())

        guard let audioGraph = self.audioGraph else { return }
        var status = noErr

        self.bufferContext.with { context in
            context.buffer.clear()
        }

        status = AUGraphStop(audioGraph)
        if status != noErr {
            print("AudioPlayerRenderer", "AUGraphStop error \(status)")
        }

        status = AUGraphUninitialize(audioGraph)
        if status != noErr {
            print("AudioPlayerRenderer", "AUGraphUninitialize error \(status)")
        }

        status = AUGraphClose(audioGraph)
        if status != noErr {
            print("AudioPlayerRenderer", "AUGraphClose error \(status)")
        }

        status = DisposeAUGraph(audioGraph)
        if status != noErr {
            print("AudioPlayerRenderer", "DisposeAUGraph error \(status)")
        }

        self.audioGraph = nil
        self.timePitchAudioUnit = nil
        self.mixerAudioUnit = nil
        self.equalizerAudioUnit = nil
        self.outputAudioUnit = nil
    }
}

private func audioRendererNativeStreamDescription() -> AudioStreamBasicDescription {
    var canonicalBasicStreamDescription = AudioStreamBasicDescription()
    canonicalBasicStreamDescription.mSampleRate = 44100.00
    canonicalBasicStreamDescription.mFormatID = kAudioFormatLinearPCM
    canonicalBasicStreamDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked
    canonicalBasicStreamDescription.mFramesPerPacket = 1
    canonicalBasicStreamDescription.mChannelsPerFrame = 2
    canonicalBasicStreamDescription.mBytesPerFrame = 2 * 2
    canonicalBasicStreamDescription.mBitsPerChannel = 8 * 2
    canonicalBasicStreamDescription.mBytesPerPacket = 2 * 2
    return canonicalBasicStreamDescription
}

final class StreamAudioRenderer {
    // MARK: - Properties

    let audioTimebase: CMTimebase
    private let audioClock: CMClock?
    private let audioPlayerRendererQueue: Queue

    private var contextRef: Unmanaged<AudioPlayerRendererContext>?

    // MARK: - Init

    init(baseRate: Double, soundMuted: Bool, queue: Queue, updateRate: @escaping () -> Void, audioPaused: @escaping () -> Void) {
        var audioClock: CMClock?
        CMAudioClockCreate(allocator: nil, clockOut: &audioClock)
        if audioClock == nil {
            audioClock = CMClockGetHostTimeClock()
        }
        self.audioClock = audioClock!

        var audioTimebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: audioClock!, timebaseOut: &audioTimebase)
        self.audioTimebase = audioTimebase!

        self.audioPlayerRendererQueue = queue

        audioPlayerRendererQueue.async {
            let context = AudioPlayerRendererContext(controlTimebase: audioTimebase!, baseRate: baseRate, soundMuted: soundMuted, queue: queue, updatedRate: updateRate, audioPaused: audioPaused)
            self.contextRef = Unmanaged.passRetained(context)
        }
    }

    deinit {
        let contextRef = contextRef
        audioPlayerRendererQueue.async {
            contextRef?.release()
        }
    }

    // MARK: - Interface

    func start() {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.start()
            }
        }
    }

    func stop() {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.stop()
            }
        }
    }

    func setBaseRate(_ baseRate: Double) {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.setBaseRate(baseRate)
            }
        }
    }

    func setRate(_ rate: Double) {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.setRate(rate)
            }
        }
    }

    func setSoundMuted(_ soundMuted: Bool) {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.setSoundMuted(soundMuted: soundMuted)
            }
        }
    }

    func setVolume(_ volume: Double) {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.setVolume(volume)
            }
        }
    }

    func beginRequestingFrames(queue: DispatchQueue, takeFrame: @escaping () -> MediaTrackFrameResult) {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.beginRequestingFrames(queue: queue, takeFrame: takeFrame)
            }
        }
    }

    func endRequestingFrames() {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.endRequestingFrames()
            }
        }
    }

    func flushBuffers(at timestamp: CMTime, completion: @escaping () -> Void) {
        audioPlayerRendererQueue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                context.flushBuffers(at: timestamp, completion: completion)
            }
        }
    }
}
