//
//  StreamSessionMultipleContext.swift
//  StreamKit
//
//  Created by Nikita Bondar on 25.10.2024.
//

import Foundation
import SwiftSignalKit

private enum SegmentDownloaderError: Error {
    // MARK: - Cases

    case some(Error)
    case unknown
}

private final class SegmentDownloader {
    // MARK: - Properties

    private let fileManager: FileManager
    private let session: URLSession
    private let queue: Queue

    private let directoryPath: String

    private var tasks: [String: URLSessionTask] = [:]

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

    func download(_ segment: StreamInfo.Segment, content: StreamSessionManifestContent, manifestUrl: URL) -> Signal<StreamSegmentFile, SegmentDownloaderError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }

            let id = segment.uri
            let segmentUrl = manifestUrl.deletingLastPathComponent().appendingPathComponent(segment.uri)
            let request = URLRequest(url: segmentUrl)

            let task = self.session.downloadTask(with: request) { [weak self] localUrl, response, error in
                guard let self else { return }

                self.queue.async { [weak self] in
                    guard let self else { return }
                    defer { self.tasks.removeValue(forKey: id) }

                    if let localUrl = localUrl {
                        let segmentDirectoryPath = segment.uri.directoryPath()
                        let directoryPath: String
                        if segmentDirectoryPath.isEmpty {
                            directoryPath = self.directoryPath.appending("/\(content.path)")
                        } else {
                            directoryPath = self.directoryPath.appending("/\(content.path)").appending( "/\(segmentDirectoryPath)")
                        }
                        try? self.fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)

                        let segmentPath = directoryPath.appending("/\(segment.uri.fileName())")
                        do {
                            try self.fileManager.copyItem(atPath: localUrl.path, toPath: segmentPath)
                            try? self.fileManager.removeItem(at: localUrl)

                            subscriber.putNext(StreamSegmentFile(id: id, content: content, duration: segment.duration, path: segmentPath, startTime: segment.startTime, title: segment.title))
                            subscriber.putCompletion()
                        } catch {
                            try? self.fileManager.removeItem(at: localUrl)
                            subscriber.putError(.some(error))
                        }
                    } else if let error = error {
                        subscriber.putError(.some(error))
                    } else {
                        subscriber.putError(.unknown)
                    }

                    self.tasks.removeValue(forKey: id)
                }
            }

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

final class StreamSessionMultipleContext: StreamSessionContext {
    // MARK: - Children

    private struct Task {
        // MARK: - Properties

        let content: StreamSessionManifestContent
        let segment: StreamInfo.Segment
    }

    // MARK: - Properties

    var seeked: Signal<Void, NoError> { seekPipe.signal() }
    private let seekPipe: ValuePipe<Void>

    var reserveTimeUpdated: Signal<Double, NoError> { reserveTimePipe.signal() }
    private let reserveTimePipe: ValuePipe<Double>

    var headerFileDownloaded: Signal<StreamHeaderFile, NoError> { .never() }

    var segmentFileDownloaded: Signal<StreamSegmentFile, NoError> { segmentFilePipe.signal() }
    private let segmentFilePipe: ValuePipe<StreamSegmentFile>

    var stateUpdated: Signal<StreamSessionContextState, NoError> { statePipe.signal() }
    private var state: StreamSessionContextState
    private let statePipe: ValuePipe<StreamSessionContextState>

    private var audio: StreamSessionManifest?
    private var video: StreamSessionManifest?

    private let fileManager: FileManager
    private let downloader: SegmentDownloader
    private let queue: Queue

    private let audioSegments: SegmentFileCollection
    private let videoSegments: SegmentFileCollection

    private let currentTimeGop: TimeInterval = 25.0
    private var currentTime: TimeInterval = 0.0

    private var tasks: [Task] = []

    private var disposable: DisposableSet

    // MARK: - Init

    init(fileManager: FileManager, session: URLSession, queue: Queue) {
        self.fileManager = fileManager
        self.downloader = SegmentDownloader(fileManager: fileManager, session: session, queue: queue)
        self.queue = queue

        seekPipe = ValuePipe()

        reserveTimePipe = ValuePipe()

        segmentFilePipe = ValuePipe()

        state = .idle
        statePipe = ValuePipe()

        audioSegments = SegmentFileCollection()
        videoSegments = SegmentFileCollection()

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

            if let audio = self.audio {
                self.downloadNextSegments(audio, content: .audio)
            }
            if let video = self.video {
                self.downloadNextSegments(video, content: .video)
            }

            self.cleanOutdatedFiles()
            self.checkState()
        }
    }

    func seek(to time: TimeInterval) {
        queue.async { [weak self] in
            guard let self, let manifest = self.video ?? self.audio else { return }

            self.currentTime = max(0.0, min(manifest.info.duration, time))

            if let fas = self.audioSegments.first,
               let las = self.audioSegments.last,
               let fvs = self.videoSegments.first,
               let lvs = self.videoSegments.last,
               fas.startTime <= time && time <= las.startTime + las.duration,
               fvs.startTime <= time && time <= lvs.startTime + lvs.duration {
                self.seekPipe.putNext(())

                if let audioSegmentIndex = self.audioSegments.firstIndex(where: { $0.startTime <= time && time <= $0.startTime + $0.duration }) {
                    var index = audioSegmentIndex
                    while index < self.audioSegments.count {
                        self.segmentFilePipe.putNext(self.audioSegments.file(at: index))
                        index = self.audioSegments.index(after: index)
                    }
                } else {
                    if let audio = self.audio {
                        self.downloadNextSegments(audio, content: .audio)
                    }
                }

                if let videoSegmentIndex = self.videoSegments.firstIndex(where: { $0.startTime <= time && time <= $0.startTime + $0.duration }) {
                    var index = videoSegmentIndex
                    while index < self.videoSegments.count {
                        self.segmentFilePipe.putNext(self.videoSegments.file(at: index))
                        index = self.videoSegments.index(after: index)
                    }
                } else {
                    if let video = self.video {
                        self.downloadNextSegments(video, content: .video)
                    }
                }
            } else {
                self.cleanAllFiles()
                self.tasks.removeAll()
                self.seekPipe.putNext(())

                if let audio = self.audio {
                    self.downloadNextSegments(audio, content: .audio)
                }
                if let video = self.video {
                    self.downloadNextSegments(video, content: .video)
                }
            }

            self.checkState()
        }
    }

    func set(manifest: StreamSessionManifest, for content: StreamSessionManifestContent) {
        queue.async { [weak self] in
            guard let self else { return }

            switch content {
            case .audio:
                self.audio = manifest
            case .video:
                self.video = manifest
            default:
                break
            }
            self.downloadNextSegments(manifest, content: content)
            self.checkState()
        }
    }

    func reset(for content: StreamSessionManifestContent) {
        queue.async { [weak self] in
            guard let self else { return }

            self.cleanContentFiles(content)
            self.tasks.removeAll(where: { $0.content == content })

            self.checkState()
        }
    }

    func clean() {
        queue.async { [weak self] in
            guard let self else { return }

            self.currentTime = 0.0

            self.disposable.dispose()

            self.audio = nil
            self.video = nil

            self.disposable = DisposableSet()
            self.updateState(.idle)

            self.tasks.removeAll()

            self.cleanAllFiles()
        }
    }

    // MARK: - Private. Load

    private func downloadNextSegments(_ manifest: StreamSessionManifest, content: StreamSessionManifestContent) {
        guard !tasks.contains(where: { $0.content == content }) else { return }
        guard let segment = findNextSegmentToDownload(in: manifest, segmentFiles: content == .audio ? audioSegments : videoSegments) else { return }
        guard !tasks.contains(where: { $0.segment.uri == segment.uri }), segment.startTime < currentTime + currentTimeGop else { return }

        let task = Task(content: content, segment: segment)
        tasks.append(task)

        print("-- download next start: \(task.segment.uri), content: \(content), start: \(segment.startTime)")
        disposable.add((downloader.download(segment, content: content, manifestUrl: manifest.url) |> deliverOn(queue)).start(next: { [weak self] file in
            guard let self else { return }

            self.reserveTimePipe.putNext(max(0.0, file.startTime + file.duration - self.currentTime))

            if let taskIndex = self.tasks.firstIndex(where: { $0.segment.uri == segment.uri }) {
                self.tasks.remove(at: taskIndex)

                switch file.content {
                case .audio:
                    self.audioSegments.append(file)
                case .video:
                    self.videoSegments.append(file)
                default:
                    break
                }
                self.segmentFilePipe.putNext(file)

                self.downloadNextSegments(manifest, content: content)
                self.checkState()
            } else {
                try? self.fileManager.removeItem(atPath: file.path)
            }
        }, error: { [weak self] error in
            guard let self else { return }
            self.tasks.removeAll(where: { $0.segment.uri == segment.uri })
        }))
    }

    // MARK: - Private. Finders

    private func findNextSegmentToDownload(in manifest: StreamSessionManifest, segmentFiles: SegmentFileCollection) -> StreamInfo.Segment? {
        if !segmentFiles.isEmpty {
            let targetEndTime = segmentFiles.last.flatMap { $0.startTime + $0.duration } ?? 0.0
            if let items = manifest.info.items, !items.isEmpty {
                return items.firstSegment(where: { $0.startTime >= targetEndTime && !segmentFiles.contains($0.id) })
            }
        } else {
            let targetTime = currentTime
            if let items = manifest.info.items, !items.isEmpty {
                return items.firstSegment(where: { $0.startTime <= targetTime && targetTime <= $0.startTime + $0.duration && !segmentFiles.contains($0.id) })
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

    private func cleanAllFiles() {
        audioSegments.forEach { try? fileManager.removeItem(atPath: $0.path) }
        audioSegments.clean()

        videoSegments.forEach { try? fileManager.removeItem(atPath: $0.path) }
        videoSegments.clean()
    }

    private func cleanContentFiles(_ content: StreamSessionManifestContent) {
        switch content {
        case .audio:
            audioSegments.forEach { try? fileManager.removeItem(atPath: $0.path) }
            audioSegments.clean()
        case .video:
            videoSegments.forEach { try? fileManager.removeItem(atPath: $0.path) }
            videoSegments.clean()
        default:
            break
        }
    }

    private func cleanOutdatedFiles() {
        for segments in [audioSegments, videoSegments] {
            while !segments.isEmpty {
                let segmentFile = segments.file(at: 0)
                let endTime = segmentFile.startTime + segmentFile.duration
                if endTime < currentTime - currentTimeGop {
                    try? fileManager.removeItem(atPath: segmentFile.path)
                    segments.remove(at: 0)
                    continue
                }
                break
            }
        }
    }

    // MARK: - Private. Checks

    private func checkState() {
        let audioFile = audioSegments.last
        let videoFile = videoSegments.last

        let audioEnded = checkFileIsEndOfStream(audioFile, manifest: audio)
        let videoEnded = checkFileIsEndOfStream(videoFile, manifest: video)

        if audioEnded, videoEnded {
            updateState(.finished)
            return
        }

        let items: [(file: StreamSegmentFile?, manifest: StreamSessionManifest?)] = [(audioFile, audio), (videoFile, video)]
        for item in items {
            if let file = item.file, file.startTime + file.duration <= currentTime {
                updateState(.downloading)
                return
            } else if item.manifest != nil, item.file == nil {
                updateState(.downloading)
                return
            }
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

private extension Array where Element == StreamInfo.Item {
    // MARK: - Interface

    func firstSegment(where predicate: (StreamInfo.Segment) -> Bool) -> StreamInfo.Segment? {
        for item in self {
            if case let .segment(segment) = item, predicate(segment) {
                return segment
            }
        }
        return nil
    }
}
