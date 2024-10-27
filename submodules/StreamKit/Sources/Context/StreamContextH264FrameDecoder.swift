//
//  StreamContextH264FrameDecoder.swift
//  TelegramMediaPlayer
//
//  Created by Nikita Bondar on 16.10.2024.
//

import CoreMedia
import FFMpegBinding
import SwiftSignalKit
import VideoToolbox

/*
 // debug panel code
 let offset = 16; var i = 0; while i < Int(frame.packet.size) { var text = ""; for j in 0 ..< offset { if i + j < Int(frame.packet.size) { text += " \(String(format: "%02X", frame.packet.data[i + j]))" } }; print(text); i += offset }
 */

private enum H264Error: Error, CustomStringConvertible {
    // MARK: - Cases

    case InvalidDecoderData
    case InvalidDecoderImage
    case InvalidNALUType
    case VideoSessionNotReady
    case Memory
    case NALUMissed
    case CMBlockBufferCreateWithMemoryBlock(OSStatus)
    case CMBlockBufferAppendBufferReference(OSStatus)
    case CMSampleBufferCreateReady(OSStatus)
    case VTDecompressionSessionDecodeFrame(OSStatus)
    case CMVideoFormatDescriptionCreateFromH264ParameterSets(OSStatus)
    case VTDecompressionSessionCreate(OSStatus)
    case InvalidCVImageBuffer
    case InvalidCVPixelBufferFormat

    // MARK: - Properties

    var description : String {
        switch self {
        case .InvalidDecoderData: return "H264Error.InvalidDecoderData"
        case .InvalidDecoderImage: return "H264Error.InvalidDecoderImage"
        case .InvalidNALUType: return "H264Error.InvalidNALUType"
        case .VideoSessionNotReady: return "H264Error.VideoSessionNotReady"
        case .Memory: return "H264Error.Memory"
        case .NALUMissed: return "NALU missed when parsing"
        case let .CMBlockBufferCreateWithMemoryBlock(status): return "H264Error.CMBlockBufferCreateWithMemoryBlock(\(status))"
        case let .CMBlockBufferAppendBufferReference(status): return "H264Error.CMBlockBufferAppendBufferReference(\(status))"
        case let .CMSampleBufferCreateReady(status): return "H264Error.CMSampleBufferCreateReady(\(status))"
        case let .VTDecompressionSessionDecodeFrame(status): return "H264Error.VTDecompressionSessionDecodeFrame(\(status))"
        case let .CMVideoFormatDescriptionCreateFromH264ParameterSets(status): return "H264Error.CMVideoFormatDescriptionCreateFromH264ParameterSets(\(status))"
        case let .VTDecompressionSessionCreate(status): return "H264Error.VTDecompressionSessionCreate(\(status))"
        case .InvalidCVImageBuffer: return "H264Error.InvalidCVImageBuffer"
        case .InvalidCVPixelBufferFormat: return "H264Error.InvalidCVPixelBufferFormat"
        }
    }
}

private enum NALUType : UInt8, CustomStringConvertible {
    // MARK: - Cases

    case Undefined = 0
    case CodedSlice = 1
    case DataPartitionA = 2
    case DataPartitionB = 3
    case DataPartitionC = 4
    case IDR = 5 // (Instantaneous Decoding Refresh) Picture
    case SEI = 6 // (Supplemental Enhancement Information)
    case SPS = 7 // (Sequence Parameter Set)
    case PPS = 8 // (Picture Parameter Set)
    case AccessUnitDelimiter = 9
    case EndOfSequence = 10
    case EndOfStream = 11
    case FilterData = 12
    // 13-23 [extended]
    // 24-31 [unspecified]

    // MARK: - Properties

    var description : String {
        switch self {
        case .CodedSlice: return "CodedSlice"
        case .DataPartitionA: return "DataPartitionA"
        case .DataPartitionB: return "DataPartitionB"
        case .DataPartitionC: return "DataPartitionC"
        case .IDR: return "IDR"
        case .SEI: return "SEI"
        case .SPS: return "SPS"
        case .PPS: return "PPS"
        case .AccessUnitDelimiter: return "AccessUnitDelimiter"
        case .EndOfSequence: return "EndOfSequence"
        case .EndOfStream: return "EndOfStream"
        case .FilterData: return "FilterData"
        default: return "Undefined"
        }
    }
}

private final class NALU {
    // MARK: - Properties

    var naluTypeName : String {
        type.description
    }

    let buffer: UnsafeBufferPointer<UInt8>
    let type : NALUType
    let priority : Int

    private var bbuffer: CMBlockBuffer!
    private var bbdata: UnsafeMutablePointer<UInt8>?
    private var bblen = [UInt8](repeating: 0, count: 8)

    private var copied = false

    // MARK: - Init

    init(_ buffer: UnsafeBufferPointer<UInt8>) {
        var type : NALUType?
        var priority : Int?
        self.buffer = buffer
        if buffer.count > 0 {
            let hb = buffer[0]
            if (((hb >> 7) & 0x01) == 0) { // zerobit
                type = NALUType(rawValue: (hb >> 0) & 0x1F) // type
                priority = Int((hb >> 5) & 0x03) // priority
            }
        }
        self.type = type == nil ? .Undefined : type!
        self.priority = priority == nil ? 0 : priority!
    }

    deinit {
        if copied {
            free(UnsafeMutablePointer<UInt8>(mutating: buffer.baseAddress))
        }
        if bbdata != nil {
            free(bbdata)
        }
    }

    convenience init(){
        self.init(UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(bitPattern: 0), count: 0))
    }

    convenience init(_ bytes: UnsafePointer<UInt8>, length: Int) {
        self.init(UnsafeBufferPointer<UInt8>(start: bytes, count: length))
    }

    // MARK: - Interface

    func copy() -> NALU {
        let baseAddress = UnsafeMutablePointer<UInt8>.allocate(capacity: buffer.count)
        memcpy(baseAddress, buffer.baseAddress, buffer.count)
        let nalu = NALU(baseAddress, length: buffer.count)
        nalu.copied = true
        return nalu
    }

    func equals(nalu: NALU) -> Bool {
        if nalu.buffer.count != buffer.count {
            return false
        }
        return memcmp(nalu.buffer.baseAddress, buffer.baseAddress, buffer.count) == 0
    }
}

private final class Packet {
    // MARK: - Properties

    private(set) var buffer: UnsafePointer<UInt8>
    private(set) var bufferSize: Int
    private(set) var fps: Int

    // MARK: - Init

    convenience init(_ data: NSData, fps: Int) {
        let buffer = data as Data
        self.init(buffer, fps: fps)
    }

    convenience init(_ data: Data, fps: Int) {
        let buffer = [UInt8](data)
        self.init(buffer, fps: fps)
    }

    convenience init(_ data: [UInt8], fps: Int) {
        let uint8Pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        uint8Pointer.initialize(from: data, count:data.count)
        let buffer = UnsafePointer(uint8Pointer)
        self.init(buffer, bufferSize: data.count, fps: fps)
        buffer.deallocate()
    }

    init(_ buffer: UnsafePointer<UInt8>, bufferSize: Int, fps: Int) {
        self.buffer = buffer.copy(capacity: bufferSize)
        self.bufferSize = bufferSize
        self.fps = fps
    }

    deinit {
        buffer.deallocate()
    }
}

private extension Packet {
    // MARK: - Static. Interface

    static func == (lhs: Packet, rhs: Packet) -> Bool {
        if lhs.bufferSize != rhs.bufferSize {
            return false
        }
        return memcmp(lhs.buffer, rhs.buffer, lhs.bufferSize) == 0
    }

    static func != (lhs: Packet, rhs: Packet) -> Bool {
        if lhs.bufferSize != rhs.bufferSize {
            return true
        }
        return memcmp(lhs.buffer, rhs.buffer, lhs.bufferSize) != 0
    }
}


private final class PacketReader {
    // MARK: - Interface

    func read(_ frame: MediaTrackDecodableFrame) -> [Packet]? {
        guard frame.packet.size > 4, isStartOfNALU(frame.packet.data, idx: 0) else { return nil }

        let size = Int(frame.packet.size)

        // if sps || pps
        var needPreventEmulationBytes = frame.packet.size > 4 && (frame.packet.data[4] == 0x67 || frame.packet.data[4] == 0x68)

        var packets: [Packet] = []
        var index = 4
        var startIndex = 4
        var ranges: [(start: Int, end: Int)] = []
        while index + 3 < size {
            if needPreventEmulationBytes, isEmulationPreventingBytes(frame.packet.data, idx: index) {
                ranges.append((startIndex, index + 2))
                index += 3
                startIndex = index
            } else if isStartOfNALU(frame.packet.data, idx: index) {
                // if sps || pps
                needPreventEmulationBytes = index + 4 < size && (frame.packet.data[index + 4] == 0x67 || frame.packet.data[index + 4] == 0x68)

                ranges.append((startIndex, index))
                let data = copy(frame, ranges: ranges)
                packets.append(Packet(data, fps: 24))
                ranges = []

                index += 4
                startIndex = index
            } else if isStartOfImage(frame.packet.data, idx: index) {
                needPreventEmulationBytes = false

                ranges.append((startIndex, index))
                let data = copy(frame, ranges: ranges)
                packets.append(Packet(data, fps: 24))
                ranges = []

                index += 3
                startIndex = index
            } else {
                index += 1
            }
        }

        if index > startIndex {
            ranges.append((startIndex, size))
            let data = copy(frame, ranges: ranges)
            packets.append(Packet(data, fps: 24))
        }

        return packets
    }


    // MARK: - Private. System

    private func copy(_ frame: MediaTrackDecodableFrame, ranges: [(start: Int, end: Int)]) -> [UInt8] {
        let count = ranges.reduce(0, { $0 + ($1.end - $1.start) })
        var data: [UInt8] = Array(repeating: 0, count: count)
        var index = 0
        for range in ranges {
            memcpy(&data[index], &frame.packet.data[range.start], range.end - range.start)
            index += (range.end - range.start)
        }
        return data
    }

    // MARK: - Private. Help

    private func isEmulationPreventingBytes(_ pointer: UnsafeMutablePointer<UInt8>, idx: Int) -> Bool {
        pointer[idx] == 0 && pointer[idx + 1] == 0 && pointer[idx + 2] == 3
    }

    private func isStartOfNALU(_ pointer: UnsafeMutablePointer<UInt8>, idx: Int) -> Bool {
        pointer[idx] == 0 && pointer[idx + 1] == 0 && pointer[idx + 2] == 0 && pointer[idx + 3] == 1
    }

    private func isStartOfImage(_ pointer: UnsafeMutablePointer<UInt8>, idx: Int) -> Bool {
        pointer[idx] == 0 && pointer[idx + 1] == 0 && pointer[idx + 2] == 1
    }
}

private enum DecoderError: Error, CustomStringConvertible {
    // MARK: - Cases

    case InvalidDecoderData
    case InvalidDecoderImage
    case InvalidNALUType
    case VideoSessionNotReady
    case Memory
    case NALUMissed
    case CMBlockBufferCreateWithMemoryBlock(OSStatus)
    case CMBlockBufferAppendBufferReference(OSStatus)
    case CMSampleBufferCreateReady(OSStatus)
    case VTDecompressionSessionDecodeFrame(OSStatus)
    case CMVideoFormatDescriptionCreateFromH264ParameterSets(OSStatus)
    case VTDecompressionSessionCreate(OSStatus)
    case InvalidCVImageBuffer
    case InvalidCVPixelBufferFormat

    case NoImage

    // MARK: - Properties

    var description : String {
        switch self {
        case .InvalidDecoderData: return "H264Error.InvalidDecoderData"
        case .InvalidDecoderImage: return "H264Error.InvalidDecoderImage"
        case .InvalidNALUType: return "H264Error.InvalidNALUType"
        case .VideoSessionNotReady: return "H264Error.VideoSessionNotReady"
        case .Memory: return "H264Error.Memory"
        case .NALUMissed: return "NALU missed when parsing"
        case let .CMBlockBufferCreateWithMemoryBlock(status): return "H264Error.CMBlockBufferCreateWithMemoryBlock(\(status))"
        case let .CMBlockBufferAppendBufferReference(status): return "H264Error.CMBlockBufferAppendBufferReference(\(status))"
        case let .CMSampleBufferCreateReady(status): return "H264Error.CMSampleBufferCreateReady(\(status))"
        case let .VTDecompressionSessionDecodeFrame(status): return "H264Error.VTDecompressionSessionDecodeFrame(\(status))"
        case let .CMVideoFormatDescriptionCreateFromH264ParameterSets(status): return "H264Error.CMVideoFormatDescriptionCreateFromH264ParameterSets(\(status))"
        case let .VTDecompressionSessionCreate(status): return "H264Error.VTDecompressionSessionCreate(\(status))"
        case .InvalidCVImageBuffer: return "H264Error.InvalidCVImageBuffer"
        case .InvalidCVPixelBufferFormat: return "H264Error.InvalidCVPixelBufferFormat"
        case .NoImage: return "NoImage"
        }
    }


}

private final class Decoder {
    // MARK: - Children

    struct RawNalu {
        // MARK: - Children

        struct Buffer {
            let data: UnsafePointer<UInt8>
            let length: Int
        }

        // MARK: - Properties

        let buffer: Buffer
        let timingInfo: CMSampleTimingInfo
    }

    struct State {
        // MARK: - Properties

        let formatDescription: CMVideoFormatDescription
        let session: VTDecompressionSession
    }

    // MARK: - Properties

    var frameDecoded: ((CVPixelBuffer, CMTime, CMTime) -> Void)?
    var errorOccurred: ((Error) -> Void)?

    private var state: State?

    private var sps: NALU?
    private var pps: NALU?

    private var mutex = pthread_mutex_t()
    private var cond = pthread_cond_t()

    private var processing = false
    private var processingError: Error?
    private var processingBuffer: CVPixelBuffer?

    // MARK: - Init

    init() {
    }

    deinit {
        invalidate()
    }

    // MARK: - Interface

    func decode(_ rawNalus: [RawNalu]) throws -> CVPixelBuffer {
        var nalus: [RawNalu] = []
        var timings: [CMSampleTimingInfo] = []
        for rawNalu in rawNalus {
            let nalu = NALU(rawNalu.buffer.data, length: rawNalu.buffer.length)
            if nalu.type == .Undefined {
                throw H264Error.InvalidNALUType
            }

            if [.IDR, .CodedSlice].contains(nalu.type) {
                nalus.append(rawNalu)
                timings.append(rawNalu.timingInfo)
            }

            if nalu.type == .SPS {
                sps = nalu.copy()
            }

            if nalu.type == .PPS {
                pps = nalu.copy()
            }

            if let sps = sps, let pps = pps {
                let formatDescription = try createFormatDescription(pps: pps, sps: sps)

                if let state = state {
                    if !VTDecompressionSessionCanAcceptFormatDescription(state.session, formatDescription: formatDescription) {
                        invalidate()

                        let session = try createSession(formatDescription)
                        self.state = State(formatDescription: formatDescription, session: session)
                    }
                } else {
                    let session = try createSession(formatDescription)
                    self.state = State(formatDescription: formatDescription, session: session)
                }

                self.sps = nil
                self.pps = nil

                continue
            }
        }

        guard let state = state else {
            throw H264Error.VideoSessionNotReady
        }

        for (i, rawNalu) in nalus.enumerated() {
            let timing = timings[i]
            return try processNalu(rawNalu, timing: timing, state: state)
        }

        throw DecoderError.NoImage
    }

    func decompressionOutputCallback(
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTDecodeInfoFlags,
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp: CMTime,
        presentationDuration: CMTime
    ) {
        pthread_mutex_lock(&mutex)
        defer {
            processing = false
            pthread_cond_broadcast(&cond)
            pthread_mutex_unlock(&mutex)
        }
        if status != noErr {
            processingError = H264Error.VTDecompressionSessionDecodeFrame(status)
            return
        }
        if imageBuffer == nil {
            processingError = H264Error.InvalidCVImageBuffer
            return
        }
        //print("decode time: \(CACurrentMediaTime() - decodeTime)")

        let pixelBuffer = unsafeBitCast(Unmanaged.passUnretained(imageBuffer!).toOpaque(), to: CVPixelBuffer.self)
        processingBuffer = pixelBuffer
    }

    // MARK: - Private. System

    private func processNalu(_ rawNalu: RawNalu, timing: CMSampleTimingInfo, state: State) throws -> CVPixelBuffer {
        var videoData: [UInt8] = Array(repeating: 0, count: rawNalu.buffer.length)
        memcpy(&videoData[0], rawNalu.buffer.data, rawNalu.buffer.length)

        var bigLen = CFSwapInt32HostToBig(UInt32(rawNalu.buffer.length))
        videoData.insert(contentsOf: withUnsafeBytes(of: &bigLen, { Array($0) }), at: 0)

        let sampleSize = videoData.count

        var blockBuffer: CMBlockBuffer?
        let count = videoData.count
        var status = videoData.withUnsafeMutableBufferPointer { bufferPointer in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: bufferPointer.baseAddress!,
                blockLength: count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        if status != noErr {
            throw H264Error.CMBlockBufferCreateWithMemoryBlock(status)
        }

        var timings = [timing]
        var sampleSizes = [sampleSize]

        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: state.formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timings,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizes,
            sampleBufferOut: &sampleBuffer
        )
        if status != noErr {
            throw H264Error.CMSampleBufferCreateReady(status)
        }
        defer { CMSampleBufferInvalidate(sampleBuffer!) }

        pthread_mutex_lock(&mutex)
        processing = true
        processingError = nil
        processingBuffer = nil
        pthread_mutex_unlock(&mutex)

        status = VTDecompressionSessionDecodeFrame(state.session, sampleBuffer: sampleBuffer!, flags: [], frameRefcon: nil, infoFlagsOut: nil)
        if status != noErr {
            throw H264Error.VTDecompressionSessionDecodeFrame(status)
        }

        pthread_mutex_lock(&mutex)
        while processing {
            pthread_cond_wait(&cond, &mutex)
        }
        let error = processingError
        let decompressedPixelBuffer = processingBuffer
        pthread_mutex_unlock(&mutex)

        if error != nil {
            throw error!
        }
        if let decompressedPixelBuffer = decompressedPixelBuffer {
            return decompressedPixelBuffer
        }
        throw DecoderError.NoImage
    }

    // MARK: - Private. Help

    private func createFormatDescription(pps: NALU, sps: NALU) throws -> CMFormatDescription {
        var _formatDescription: CMFormatDescription?

        let parameterSetPointers: [UnsafePointer<UInt8>] = [ pps.buffer.baseAddress!, sps.buffer.baseAddress! ]
        let parameterSetSizes = [ pps.buffer.count, sps.buffer.count ]

        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &_formatDescription
        )
        if status != noErr {
            throw H264Error.CMVideoFormatDescriptionCreateFromH264ParameterSets(status)
        }

        return _formatDescription!
    }

    private func createSession(_ formatDescription: CMVideoFormatDescription) throws -> VTDecompressionSession {
        var session: VTDecompressionSession?

        let decoderParameters = NSMutableDictionary()

        let destinationPixelBufferAttributes = NSMutableDictionary()
        destinationPixelBufferAttributes.setValue(NSNumber(booleanLiteral: true), forKey: kCVPixelBufferMetalCompatibilityKey as String)

        var outputCallback = VTDecompressionOutputCallbackRecord()
        outputCallback.decompressionOutputCallback = callback
        outputCallback.decompressionOutputRefCon = Unmanaged.passUnretained(self).toOpaque()

        let status = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDescription,
            decoderSpecification: decoderParameters,
            imageBufferAttributes: destinationPixelBufferAttributes,
            outputCallback: &outputCallback,
            decompressionSessionOut: &session
        )
        if status != noErr {
            throw H264Error.VTDecompressionSessionCreate(status)
        }

        return session!
    }

    private func invalidate() {
        if let state = state {
            self.state = nil
            VTDecompressionSessionInvalidate(state.session)
        }
        sps = nil
        pps = nil
    }
}

// UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, OSStatus, VTDecodeInfoFlags, CVImageBuffer?, CMTime, CMTime
private func callback(decompressionOutputRefCon: UnsafeMutableRawPointer?, sourceFrameRefCon: UnsafeMutableRawPointer?, status: OSStatus, infoFlags: VTDecodeInfoFlags, imageBuffer: CVImageBuffer?, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
    unsafeBitCast(decompressionOutputRefCon, to: Decoder.self).decompressionOutputCallback(sourceFrameRefCon: sourceFrameRefCon, status: status, infoFlags: infoFlags, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, presentationDuration: presentationDuration)
}

final class StreamContextH264FrameDecoder: StreamContextFrameDecoder {
    // MARK: - Properties

    var errorOccurred: ((Error) -> Void)?

    private let decoder: Decoder
    private let packetReader: PacketReader

    // MARK: - Init

    init() {
        self.decoder = Decoder()
        self.packetReader = PacketReader()

        decoder.errorOccurred = { [weak self] error in
            guard let self else { return }
            self.errorOccurred?(error)
        }
    }

    // MARK: - Interface

    func decode(frame: MediaTrackDecodableFrame) -> MediaTrackFrame? {
        guard let packets = packetReader.read(frame) else { return nil }

        var timingInfo = CMSampleTimingInfo(duration: frame.duration, presentationTimeStamp: frame.pts, decodeTimeStamp: frame.dts)

        var rawNalus: [Decoder.RawNalu] = []
        for packet in packets {
            let buffer = Decoder.RawNalu.Buffer(data: packet.buffer, length: packet.bufferSize)
            rawNalus.append(Decoder.RawNalu(buffer: buffer, timingInfo: timingInfo))
        }

        do {
            let pixelBuffer = try decoder.decode(rawNalus)

            var formatDescription: CMVideoFormatDescription?
            var status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
            if status != noErr {
                print("video format description error: \(status)")
                return nil
            }

            var sampleBuffer: CMSampleBuffer?
            status = CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: formatDescription!,
                sampleTiming: &timingInfo,
                sampleBufferOut: &sampleBuffer
            )
            if status != noErr {
                print("sample buffer create error: \(status)")
                return nil
            }
            return MediaTrackFrame(type: .video, sampleBuffer: sampleBuffer!, decoded: true, rotationAngle: 0.0)
        } catch {
            print("decoder error: \(error)")
            errorOccurred?(error)
            return nil
        }
    }

    func reset() {
        // drop current decodes
    }
}
