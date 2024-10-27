//
//  StreamSessionSingleContext.swift
//  StreamKit
//
//  Created by Nikita Bondar on 25.10.2024.
//

import Foundation
import SwiftSignalKit

private enum ItemDownloaderError: Error {
    // MARK: - Cases

    case byteRangeNotFound
    case headerNotFound
    case some(Error)
    case unknown
}

private final class ItemDownloader {
    // MARK: - Children

    enum Content {
        // MARK: - Cases

        case header(StreamHeaderFile)
        case file(StreamSegmentFile)
    }

    // MARK: - Properties

    private let fileManager: FileManager
    private let session: URLSession
    private let queue: Queue

    private let directoryPath: String

    private var tasks: [AnyHashable: URLSessionTask] = [:]

    // MARK: - Init

    init(fileManager: FileManager, session: URLSession, queue: Queue) {
        self.fileManager = fileManager
        self.session = session
        self.queue = queue

        directoryPath = NSTemporaryDirectory().appending("segments")
        try? fileManager.removeItem(atPath: directoryPath)
        try? fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)

        for content in StreamSessionManifestContent.allCases {
            let path = directoryPath.appending("/\(content.path)")
            try? fileManager.removeItem(atPath: path)
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    deinit {
        cancel()
    }

    // MARK: - Interface

    func download(_ item: StreamInfo.Item, content: StreamSessionManifestContent, manifestUrl: URL) -> Signal<Content, ItemDownloaderError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }

            let byteRange = item.byteRange ?? .init(start: 0, length: 0)
            let byteStart = byteRange.start ?? 0
            let byteEnd = byteStart + byteRange.length

            let id = item.id
            let segmentUrl = manifestUrl.deletingLastPathComponent().appendingPathComponent(item.uri)
            var request = URLRequest(url: segmentUrl)
            request.allHTTPHeaderFields = ["Range": "bytes=\(byteStart)-\(byteEnd)"]

            let task = self.session.dataTask(with: request, completionHandler: { [weak self] data, response, error in
                guard let self else { return }

                self.queue.async { [weak self] in
                    guard let self else { return }
                    defer { self.tasks.removeValue(forKey: id) }

                    if let data = data {
                        switch item {
                        case .map:
                            let path = self.directoryPath.appending("/\(content.path)/\(item.id)").replacingExtension(".ts")
                            do {
                                try data.write(to: URL(fileURLWithPath: path))
                                subscriber.putNext(.header(StreamHeaderFile(id: item.id, content: content, startTime: item.startTime, path: path)))
                                subscriber.putCompletion()
                            } catch {
                                subscriber.putError(.some(error))
                            }

                        case let .segment(segment):
                            //guard let header = header else { subscriber.putError(.headerNotFound); return }

                            //let ptr = malloc(header.count + data.count)!
                            //var segmentBytes: [UInt8] = Array(repeating: 0, count: header.count + data.count)
                            //var segmentData = Data(bytesNoCopy: &segmentBytes[0], count: segmentBytes.count, deallocator: .none)
                            //memcpy(ptr.advanced(by: 0), &header[0], header.count)
                            //memcpy(ptr.advanced(by: header.count), &data[0], data.count)

//                            header.withUnsafeBytes { (headerPtr: UnsafeRawBufferPointer) -> Void in
//                                memcpy(ptr.advanced(by: 0), headerPtr.baseAddress, header.count)
//                            }
//                            data.withUnsafeBytes { (dataPtr: UnsafeRawBufferPointer) -> Void in
//                                memcpy(ptr.advanced(by: header.count), dataPtr.baseAddress, data.count)
//                            }

                            let segmentData = data // Data(bytesNoCopy: ptr, count: header.count + data.count, deallocator: .free)

                            let path = self.directoryPath.appending("/\(content.path)/\(item.id)").replacingExtension(".ts")
                            do {
                                try segmentData.write(to: URL(fileURLWithPath: path))
                                subscriber.putNext(.file(StreamSegmentFile(id: item.id, content: content, duration: segment.duration, path: path, startTime: segment.startTime, title: segment.title)))
                                subscriber.putCompletion()
                            } catch {
                                subscriber.putError(.some(error))
                            }
                        }

                    } else if let error = error {
                        subscriber.putError(.some(error))
                    } else {
                        subscriber.putError(.unknown)
                    }
                }
            })

            self.tasks[id] = task
            task.resume()

            return ActionDisposable { [weak self] in
                guard let self else { return }

                if let task = self.tasks[id] {
                    task.cancel()
                    self.tasks.removeValue(forKey: id)
                }
            }
        } |> runOn(queue)
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }

            for (_, task) in self.tasks {
                task.cancel()
            }
            self.tasks = [:]
        }
    }
}

private extension String {
    // MARK: - Interface

    func directoryPath() -> String {
        let components = split(separator: "/")
        if components.count > 1 {
            return String(components[0 ..< max(1, components.count - 1)].joined(separator: "/"))
        }
        return ""
    }

    func fileName() -> String {
        let components = split(separator: "/")
        if !components.isEmpty {
            return String(components.last!)
        }
        return self
    }

    func replacingExtension(_ ext: String) -> String {
        var suffix: String = ""
        var index = self.index(before: endIndex)
        while index > startIndex {
            if self[index] == "." {
                suffix.insert(self[index], at: suffix.startIndex)
                return replacingOccurrences(of: suffix, with: ext)
            }
            suffix.insert(self[index], at: suffix.startIndex)
            index = self.index(before: index)
        }
        return self
    }
}

private extension StreamSessionManifestContent {
    // MARK: - Properties

    var path: String {
        switch self {
        case .audio:
            return "audio"
        case .subtitles:
            return "subtitles"
        case .video:
            return "video"
        }
    }
}

private final class HeaderCollection {
    // MARK: - Properties

    private var ids: Set<AnyHashable> = []
    private var headers: [StreamHeaderFile] = []

    // MARK: - Interface

    func contains(_ id: AnyHashable) -> Bool {
        ids.contains(id)
    }

    func find(for time: Double) -> StreamHeaderFile? {
        var founded: Int?
        var i = 0
        while i < headers.count {
            if headers[i].startTime <= time {
                founded = i
                i += 1
            } else {
                break
            }
        }
        return founded.flatMap { headers[$0] }
    }

    func append(_ header: StreamHeaderFile) {
        ids.insert(header.id)
        headers.append(header)
    }

    func clean() {
        ids = []
        headers = []
    }
}

final class StreamSessionSingleContext: StreamSessionContext {
    // MARK: - Children

    private struct Task {
        // MARK: - Properties

        let item: StreamInfo.Item
    }

    // MARK: - Properties

    var seeked: Signal<Void, NoError> { seekPipe.signal() }
    private let seekPipe: ValuePipe<Void>

    var reserveTimeUpdated: Signal<Double, NoError> { reserveTimePipe.signal() }
    private let reserveTimePipe: ValuePipe<Double>

    var headerFileDownloaded: Signal<StreamHeaderFile, NoError> { headerFilePipe.signal() }
    private let headerFilePipe: ValuePipe<StreamHeaderFile>

    var segmentFileDownloaded: Signal<StreamSegmentFile, NoError> { segmentFilePipe.signal() }
    private let segmentFilePipe: ValuePipe<StreamSegmentFile>

    var stateUpdated: Signal<StreamSessionContextState, NoError> { statePipe.signal() }
    private var state: StreamSessionContextState
    private let statePipe: ValuePipe<StreamSessionContextState>

    private var content: StreamSessionManifestContent?
    private var manifest: StreamSessionManifest?

    private let fileManager: FileManager
    private let downloader: ItemDownloader
    private let queue: Queue

    private let headers: HeaderCollection
    private let files: SegmentFileCollection

    private let currentTimeGop: TimeInterval = 25.0
    private var currentTime: TimeInterval = 0.0

    private var tasks: [Task] = []

    private var disposable: DisposableSet

    // MARK: - Init

    init(fileManager: FileManager, session: URLSession, queue: Queue) {
        self.fileManager = fileManager
        self.downloader = ItemDownloader(fileManager: fileManager, session: session, queue: queue)
        self.queue = queue

        seekPipe = ValuePipe()

        reserveTimePipe = ValuePipe()

        headerFilePipe = ValuePipe()
        segmentFilePipe = ValuePipe()

        state = .idle
        statePipe = ValuePipe()

        headers = HeaderCollection()
        files = SegmentFileCollection()

        disposable = DisposableSet()
    }

    deinit {
        disposable.dispose()
    }

    // MARK: - Interface

    func currentTimeUpdated(_ time: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }

            self.currentTime = time

            if let manifest = self.manifest {
                self.downloadNextItems(manifest)
            }

            self.cleanOutdatedFiles()
            self.checkState()
        }
    }

    func seek(to time: TimeInterval) {
        queue.async { [weak self] in
            guard let self, let manifest = self.manifest else { return }

            self.currentTime = max(0.0, min(manifest.info.duration, time))

            if let fs = self.files.first, let ls = self.files.last,
               fs.startTime <= time && time <= ls.startTime + ls.duration {
                self.seekPipe.putNext(())

                if let segmentIndex = self.files.firstIndex(where: { $0.startTime <= time && time <= $0.startTime + $0.duration }) {
                    var index = segmentIndex
                    while index < self.files.count {
                        self.segmentFilePipe.putNext(self.files.file(at: index))
                        index = self.files.index(after: index)
                    }
                } else {
                    self.downloadNextItems(manifest)
                }
            } else {
                self.cleanFiles()
                self.tasks.removeAll()
                self.seekPipe.putNext(())

                self.downloadNextItems(manifest)
            }

            self.checkState()
        }
    }

    func set(manifest: StreamSessionManifest, for content: StreamSessionManifestContent) {
        queue.async { [weak self] in
            guard let self else { return }

            self.content = content
            self.manifest = manifest

            self.downloadNextItems(manifest)
            self.checkState()
        }
    }

    func reset(for content: StreamSessionManifestContent) {
        queue.async { [weak self] in
            guard let self else { return }

            self.cleanFiles()
            self.tasks.removeAll()

            self.checkState()
        }
    }

    func clean() {
        queue.async { [weak self] in
            guard let self else { return }

            self.currentTime = 0.0

            self.disposable.dispose()

            self.content = nil
            self.manifest = nil

            self.disposable = DisposableSet()
            self.updateState(.idle)

            self.tasks.removeAll()

            self.headers.clean()
            self.cleanFiles()
        }
    }

    // MARK: - Private. Load

    private func downloadNextItems(_ manifest: StreamSessionManifest) {
        guard tasks.isEmpty, let content = content,  let item = findNextItemToDownload(in: manifest, files: files) else { return }
        guard item.startTime < currentTime + currentTimeGop else { return }

        let task = Task(item: item)
        tasks.append(task)

        print("-- download next start: \(task.item.uri), start: \(item.startTime)")
        disposable.add((downloader.download(item, content: content, manifestUrl: manifest.url) |> deliverOn(queue)).start(next: { [weak self] content in
            guard let self else { return }

            if case let .file(file) = content {
                self.reserveTimePipe.putNext(max(0.0, file.startTime + file.duration - self.currentTime))
            }

            if let taskIndex = self.tasks.firstIndex(where: { $0.item.id == item.id }) {
                self.tasks.remove(at: taskIndex)

                switch content {
                case let .header(file):
                    self.headers.append(file)
                    self.headerFilePipe.putNext(file)

                case let .file(file):
                    self.files.append(file)
                    self.segmentFilePipe.putNext(file)
                }

                self.downloadNextItems(manifest)
                self.checkState()
            } else if case let .file(file) = content {
                try? self.fileManager.removeItem(atPath: file.path)
            }
        }, error: { [weak self] error in
            guard let self else { return }
            self.tasks.removeAll(where: { $0.item.id == item.id })
        }))
    }

    // MARK: - Private. Finders

    private func findNextItemToDownload(in manifest: StreamSessionManifest, files: SegmentFileCollection) -> StreamInfo.Item? {
        if !files.isEmpty {
            let targetEndTime = files.last.flatMap { $0.startTime + $0.duration } ?? 0.0
            if let items = manifest.info.items, !items.isEmpty {
                return items.first(where: { $0.startTime >= targetEndTime && !files.contains($0.id) && !headers.contains($0.id) })
            }
        } else {
            let targetTime = currentTime
            if let items = manifest.info.items, !items.isEmpty {
                return items.first(where: { $0.startTime <= targetTime && targetTime <= $0.startTime + $0.duration && !files.contains($0.id) && !headers.contains($0.id) })
            }
        }
        return nil
    }

    // MARK: - Private. Updates

    private func updateState(_ state: StreamSessionContextState) {
        if self.state != state {
            self.state = state
            statePipe.putNext(state)
        }
    }

    // MARK: - Private. Clean

    private func cleanFiles() {
        files.forEach { try? fileManager.removeItem(atPath: $0.path) }
        files.clean()
    }

    private func cleanOutdatedFiles() {
        while !files.isEmpty {
            let segmentFile = files.file(at: 0)
            let endTime = segmentFile.startTime + segmentFile.duration
            if endTime < currentTime - currentTimeGop {
                try? fileManager.removeItem(atPath: segmentFile.path)
                files.remove(at: 0)
                continue
            }
            break
        }
    }

    // MARK: - Private. Checks

    private func checkState() {
        let file = files.last
        let ended = checkFileIsEndOfStream(file, manifest: manifest)

        if ended {
            updateState(.finished)
            return
        }

        if let file = file, file.startTime + file.duration <= currentTime {
            updateState(.downloading)
            return
        } else if manifest != nil, file == nil {
            updateState(.downloading)
            return
        }

        updateState(.running)
    }

    private func checkFileIsEndOfStream(_ file: StreamSegmentFile?, manifest: StreamSessionManifest?) -> Bool {
        if let manifest = manifest {
            if let file = file {
                return manifest.info.ended && manifest.info.items?.last?.id == file.id
            }
            return false
        } else {
            return true
        }
    }
}

private extension StreamInfo.Item {
    // MARK: - Properties

    var startTime: Double {
        switch self {
        case let .map(map):
            return map.startTime
        case let .segment(segment):
            return segment.startTime
        }
    }

    var duration: Double {
        switch self {
        case let .map(map):
            return map.duration
        case let .segment(segment):
            return segment.duration
        }
    }

    var byteRange: StreamInfo.ByteRange? {
        switch self {
        case let .map(map):
            return map.byteRange
        case let .segment(segment):
            return segment.byteRange
        }
    }
}
