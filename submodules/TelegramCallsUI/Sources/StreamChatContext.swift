import Accelerate
import AVFoundation
import LibYuvBinding
import Postbox
import SwiftSignalKit
import TelegramVoip
import VideoToolbox
import UIKit

final class StreamChatContext {
    // MARK: - Properties

    private var fetchingInProgress: Bool = false
    private var saveInProgress: Atomic<Bool> = Atomic(value: false)

    // MARK: - Interface

    func fetchPreview(for peer: Peer, completion: @escaping (UIImage?) -> Void) {
        guard !fetchingInProgress else { return }
        fetchingInProgress = true

        Queue.concurrentBackgroundQueue().async { [weak self] in
            guard let self = self else { return }

            let preview = self.file(for: peer)
            let data = try? Data(contentsOf: URL(fileURLWithPath: preview.path))
            let image = data.flatMap { UIImage(data: $0) }

            Queue.mainQueue().async { self.fetchingInProgress = false; completion(image) }
        }
    }

    func save(_ buffer: OngoingGroupCallContext.VideoFrameData.Buffer, peer: Peer) {
        guard !saveInProgress.with({ $0 }) else { return }

        defer { _ = saveInProgress.modify { _ in false } }
        _ = saveInProgress.modify { _ in true }

        var pixelBuffer: CVPixelBuffer?

        switch buffer {
        case let .native(buffer):
            pixelBuffer = buffer.pixelBuffer

        case let .i420(buffer):
            let ioSurfaceProperties = NSMutableDictionary()
            let options = NSMutableDictionary()
            options.setObject(ioSurfaceProperties, forKey: kCVPixelBufferIOSurfacePropertiesKey as NSString)

            CVPixelBufferCreate(
                kCFAllocatorDefault,
                buffer.width,
                buffer.height,
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                options,
                &pixelBuffer
            )

            if let pixelBuffer = pixelBuffer {
                _ = copyI420BufferToNV12Buffer(buffer: buffer, pixelBuffer: pixelBuffer)
            }

        default:
            break
        }

        guard let pixelBuffer = pixelBuffer else { return }

        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        let image = cgImage.flatMap { UIImage(cgImage: $0) }
        guard let data = image?.pngData() else { return }

        let preview = file(for: peer)
        try? FileManager.default.removeItem(atPath: preview.path)

        try? data.write(to: URL(fileURLWithPath: preview.path))
    }

    // MARK: - Private. Help

    private func file(for peer: Peer) -> TempBoxFile {
        TempBox.shared.file(path: "preview", fileName: "\(peer.id.id.description).png")
    }
}

private func copyI420BufferToNV12Buffer(buffer: OngoingGroupCallContext.VideoFrameData.I420Buffer, pixelBuffer: CVPixelBuffer) -> Bool {
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
        return false
    }
    guard CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) == buffer.width else {
        return false
    }
    guard CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) == buffer.height else {
        return false
    }

    let cvRet = CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if cvRet != kCVReturnSuccess {
        return false
    }
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    guard let dstY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
        return false
    }
    let dstStrideY = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

    guard let dstUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
        return false
    }
    let dstStrideUV = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

    buffer.y.withUnsafeBytes { srcYBuffer in
        guard let srcY = srcYBuffer.baseAddress else {
            return
        }
        buffer.u.withUnsafeBytes { srcUBuffer in
            guard let srcU = srcUBuffer.baseAddress else {
                return
            }
            buffer.v.withUnsafeBytes { srcVBuffer in
                guard let srcV = srcVBuffer.baseAddress else {
                    return
                }
                libyuv_I420ToNV12(
                    srcY.assumingMemoryBound(to: UInt8.self),
                    Int32(buffer.strideY),
                    srcU.assumingMemoryBound(to: UInt8.self),
                    Int32(buffer.strideU),
                    srcV.assumingMemoryBound(to: UInt8.self),
                    Int32(buffer.strideV),
                    dstY.assumingMemoryBound(to: UInt8.self),
                    Int32(dstStrideY),
                    dstUV.assumingMemoryBound(to: UInt8.self),
                    Int32(dstStrideUV),
                    Int32(buffer.width),
                    Int32(buffer.height)
                )
            }
        }
    }

    return true
}
