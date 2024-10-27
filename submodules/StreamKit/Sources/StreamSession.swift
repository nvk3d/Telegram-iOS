//
//  StreamSession.swift
//  StreamKit
//
//  Created by Nikita Bondar on 05.10.2024.
//

import Foundation
import SwiftSignalKit

enum StreamSessionManifestContent: CaseIterable {
    // MARK: - Cases

    case audio
    case subtitles
    case video
}

enum StreamSessionManifestType: Equatable {
    // MARK: - Cases

    case master
    case child(StreamSessionManifestContent)
}

struct StreamSessionManifest {
    // MARK: - Children

    struct Audio {
        // MARK: - Properties

        let name: String
        let language: String?
        let byDefault: Bool
    }

    struct Video {
        // MARK: - Properties

        let bandwidth: Int
        let resolution: StreamInfo.StreamInfo.Resolution
    }

    // MARK: - Properties

    let id: AnyHashable
    let info: StreamInfo
    let url: URL
    let audio: Audio?
    let video: Video?
    let type: StreamSessionManifestType
}

struct StreamHeaderFile {
    // MARK: - Properties

    let id: AnyHashable
    let content: StreamSessionManifestContent
    let startTime: Double
    let path: String
}

struct StreamSegmentFile {
    // MARK: - Properties

    let id: AnyHashable
    let content: StreamSessionManifestContent
    let duration: Double
    let path: String
    let startTime: Double
    let title: String?
}

enum StreamSessionState: Equatable {
    // MARK: - Cases

    case idle
    case running
    case downloading
    case finished
    case error(Error)

    // MARK: - Static. Interface

    static func == (lhs: StreamSessionState, rhs: StreamSessionState) -> Bool {
        if case .idle = lhs, case .idle = rhs { return true }
        if case .running = lhs, case .running = rhs { return true }
        if case .downloading = lhs, case .downloading = rhs { return true }
        if case .finished = lhs, case .finished = rhs { return true }
        if case .error = lhs, case .error = rhs { return true }
        return false
    }
}

enum StreamSessionStrategy: Equatable {
    // MARK: - Cases

    case single
    case multiple
}

protocol StreamSession: AnyObject {
    // MARK: - Properties

    var audioUpdated: Signal<StreamSessionManifest, NoError> { get }
    var videoUpdated: Signal<StreamSessionManifest, NoError> { get }

    var seeked: Signal<Void, NoError> { get }

    var manifestsUpdated: Signal<[StreamSessionManifest], NoError> { get }

    var reserveTimeUpdated: Signal<Double, NoError> { get }
    var headerFileDownloaded: Signal<StreamHeaderFile, NoError> { get }
    var segmentFileDownloaded: Signal<StreamSegmentFile, NoError> { get }

    var stateUpdated: Signal<StreamSessionState, NoError> { get }
    var strategyUpdated: Signal<StreamSessionStrategy, NoError> { get }

    // MARK: - Interface

    func appDidBecomeActive()

    func currentTimeUpdated(_ time: TimeInterval)
    func seek(to time: TimeInterval)

    func set(audio: StreamSessionManifest)
    func set(video: StreamSessionManifest)
    func set(url: URL)

    func reset(for content: StreamSessionManifestContent)
    func clean()
}

final class StreamSessionImpl: StreamSession {
    // MARK: - Properties

    var audioUpdated: Signal<StreamSessionManifest, NoError> { audioPipe.signal() }
    private var audio: StreamSessionManifest?
    private let audioPipe: ValuePipe<StreamSessionManifest>

    var videoUpdated: Signal<StreamSessionManifest, NoError> { videoPipe.signal() }
    private var video: StreamSessionManifest?
    private let videoPipe: ValuePipe<StreamSessionManifest>

    var seeked: Signal<Void, NoError> { seekPipe.signal() }
    private let seekPipe: ValuePipe<Void>

    var manifestsUpdated: Signal<[StreamSessionManifest], NoError> { manifestsPipe.signal() }
    private var manifests: [StreamSessionManifest]
    private let manifestsPipe: ValuePipe<[StreamSessionManifest]>

    var reserveTimeUpdated: Signal<Double, NoError> { reserveTimePipe.signal() }
    private let reserveTimePipe: ValuePipe<Double>

    var headerFileDownloaded: Signal<StreamHeaderFile, NoError> { headerFilePipe.signal() }
    private let headerFilePipe: ValuePipe<StreamHeaderFile>

    var segmentFileDownloaded: Signal<StreamSegmentFile, NoError> { segmentFilePipe.signal() }
    private let segmentFilePipe: ValuePipe<StreamSegmentFile>

    var stateUpdated: Signal<StreamSessionState, NoError> { statePipe.signal() }
    private var state: StreamSessionState
    private let statePipe: ValuePipe<StreamSessionState>

    var strategyUpdated: Signal<StreamSessionStrategy, NoError> { strategyPipe.signal() }
    private let strategyPipe: ValuePipe<StreamSessionStrategy>

    private let fileManager: FileManager
    private let requester: StreamRequester
    private let session: URLSession
    private let queue: Queue

    private var context: StreamSessionContext?

    private var baseURL: URL?

    private var isReloadingManifests = false
    private var currentTime: TimeInterval = 0.0

    private var disposable: DisposableSet

    // MARK: - Init

    init(fileManager: FileManager, requester: StreamRequester, session: URLSession, queue: Queue) {
        self.fileManager = fileManager
        self.requester = requester
        self.session = session
        self.queue = queue

        headerFilePipe = ValuePipe()
        segmentFilePipe = ValuePipe()

        audio = nil
        audioPipe = ValuePipe()

        video = nil
        videoPipe = ValuePipe()

        seekPipe = ValuePipe()

        manifests = []
        manifestsPipe = ValuePipe()

        reserveTimePipe = ValuePipe()

        state = .idle
        statePipe = ValuePipe()

        strategyPipe = ValuePipe()

        disposable = DisposableSet()
    }

    deinit {
        disposable.dispose()
    }

    // MARK: - Interface

    func appDidBecomeActive() {
        queue.async { [weak self] in
            guard let self else { return }

            if self.state != .finished {
                self.checkManifests()
            }
        }
    }

    func currentTimeUpdated(_ time: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }

            self.currentTime = time
            self.context?.currentTimeUpdated(time)
            self.checkManifests()
        }
    }

    func seek(to time: TimeInterval) {
        queue.async { [weak self] in
            guard let self, let manifest = self.video ?? self.audio else { return }

            self.currentTime = max(0.0, min(manifest.info.duration, time))
            self.context?.seek(to: time)

            self.checkManifests()
        }
    }

    func set(audio: StreamSessionManifest) {
        queue.async { [weak self] in
            guard let self, audio.type == .child(.audio) else { return }

            self.setAudioManifest(audio)
            self.context?.set(manifest: audio, for: .audio)
        }
    }

    func set(video: StreamSessionManifest) {
        queue.async { [weak self] in
            guard let self, video.type == .child(.video) else { return }

            self.setVideoManifest(video)
            self.context?.set(manifest: video, for: .video)
        }
    }

    func set(url: URL) {
        queue.async { [weak self] in
            guard let self else { return }

            self.baseURL = url

            self.updateState(.downloading)
            self.reloadManifests()
        }
    }

    func reset(for content: StreamSessionManifestContent) {
        queue.async { [weak self] in
            guard let self else { return }

            self.context?.reset(for: content)
            self.checkManifests()
        }
    }

    func clean() {
        queue.async { [weak self] in
            guard let self else { return }

            self.baseURL = nil
            self.currentTime = 0.0

            self.requester.cancel()
            self.disposable.dispose()

            self.audio = nil
            self.video = nil
            self.manifests = []

            self.disposable = DisposableSet()
            self.updateState(.idle)

            self.context?.clean()
            self.context = nil
        }
    }

    // MARK: - Private. Load

    private func reloadManifests() {
        guard let url = baseURL, !isReloadingManifests else { return }

        isReloadingManifests = true
        disposable.add((requester.request(url) |> deliverOn(queue)).start(next: { [weak self] streamInfo in
            guard let self else { return }

            var manifests: [StreamSessionManifest] = [StreamSessionManifest(id: url.path, info: streamInfo, url: url, audio: nil, video: nil, type: .master)]
            let group = DispatchGroup()

            for media in streamInfo.media ?? [] {
                guard media.type == .audio, let uri = media.uri else { continue }

                group.enter()

                let audio = StreamSessionManifest.Audio(name: media.name, language: media.language, byDefault: media.byDefault)

                let childUrl = url.deletingLastPathComponent().appendingPathComponent(uri)
                self.disposable.add((self.requester.request(childUrl) |> deliverOn(self.queue)).start(next: { childStreamInfo in
                    manifests.append(StreamSessionManifest(id: uri, info: childStreamInfo, url: childUrl, audio: audio, video: nil, type: .child(.audio)))
                }, error: { _ in
                    group.leave()
                }, completed: {
                    group.leave()
                }))
            }

            for childInfo in streamInfo.streamInfo ?? [] {
                // prevent 4k
                guard (childInfo.resolution?.width ?? 0) < 2000, (childInfo.resolution?.height ?? 0) < 2000 else { continue }
                group.enter()

                var video: StreamSessionManifest.Video?
                if let resolution = childInfo.resolution {
                    video = .init(bandwidth: childInfo.bandwidth, resolution: resolution)
                }

                let childUrl = url.deletingLastPathComponent().appendingPathComponent(childInfo.uri)
                self.disposable.add((self.requester.request(childUrl) |> deliverOn(self.queue)).start(next: { childStreamInfo in
                    manifests.append(StreamSessionManifest(id: childInfo.uri, info: childStreamInfo, url: childUrl, audio: nil, video: video, type: .child(.video)))
                }, error: { _ in
                    group.leave()
                }, completed: {
                    group.leave()
                }))
            }

            group.notify(queue: self.queue.queue) { [weak self] in
                guard let self else { return }

                self.isReloadingManifests = false

                if self.context == nil {
                    self.updateContext(for: manifests)
                }

                self.updateManifests(manifests)
                if self.audio == nil, self.video == nil {
                    self.updateDefaultManifests(manifests)
                }
            }
        }, error: { [weak self] error in
            guard let self else { return }

            self.isReloadingManifests = false
            self.updateState(.error(error))
        }))
    }

    // MARK: - Private. Finders & Setters

    private func findBestChildManifest(in manifest: StreamSessionManifest) -> (audio: StreamSessionManifest?, video: StreamSessionManifest?)? {
        guard case .master = manifest.type else { return nil }

        var videoManifest: StreamSessionManifest?
        var preferredAudioGroupId: String?

        let streamInfos = (manifest.info.streamInfo ?? []).sorted { $0.bandwidth < $1.bandwidth }
        if let streamInfo = streamInfos.last, let video = manifests.first(where: { $0.type == .child(.video) && $0.id == AnyHashable(streamInfo.uri) }) {
            videoManifest = video
            preferredAudioGroupId = streamInfo.audio
        } else {
            videoManifest = manifests.last(where: { $0.type == .child(.video) })
        }
        
        var audioManifest: StreamSessionManifest?

        let media = manifest.info.media ?? []
        let audioMedia = media.first(where: { $0.type == .audio && $0.groupId == preferredAudioGroupId })
            ?? media.first(where: { $0.type == .audio && $0.byDefault })
            ?? media.first(where: { $0.type == .audio && $0.language == "en" })
            ?? media.first
        if let audio = manifests.first(where: { $0.id == AnyHashable(audioMedia?.uri ?? "") }) {
            audioManifest = audio
        } else {
            audioManifest = manifests.first(where: { $0.type == .child(.audio) })
        }

        return (audioManifest, videoManifest)
    }

    private func setAudioManifest(_ manifest: StreamSessionManifest) {
        audio = manifest
        context?.set(manifest: manifest, for: .audio)
        audioPipe.putNext(manifest)
    }

    private func setVideoManifest(_ manifest: StreamSessionManifest) {
        video = manifest
        context?.set(manifest: manifest, for: .video)
        videoPipe.putNext(manifest)
    }

    // MARK: - Private. Updates

    private func updateContext(for manifests: [StreamSessionManifest]) {
        let containsAudio = manifests.contains(where: { $0.type == .child(.audio) })
        let containsVideo = manifests.contains(where: { $0.type == .child(.video) })

        guard containsAudio || containsVideo else { return }

        let strategy: StreamSessionStrategy
        let context: StreamSessionContext
        if !containsAudio || !containsVideo {
            strategy = .single
            context = StreamSessionSingleContext(fileManager: fileManager, session: session, queue: queue)
        } else {
            strategy = .multiple
            context = StreamSessionMultipleContext(fileManager: fileManager, session: session, queue: queue)
        }
        disposable.add(context.seeked.start { [weak self] _ in
            guard let self else { return }
            self.seekPipe.putNext(())
        })
        disposable.add(context.reserveTimeUpdated.start { [weak self] time in
            guard let self else { return }
            self.reserveTimePipe.putNext(time)
        })
        disposable.add(context.headerFileDownloaded.start { [weak self] file in
            guard let self else { return }
            self.headerFilePipe.putNext(file)
        })
        disposable.add(context.segmentFileDownloaded.start { [weak self] file in
            guard let self else { return }
            self.segmentFilePipe.putNext(file)
        })
        disposable.add(context.stateUpdated.start { [weak self] state in
            guard let self else { return }

            switch state {
            case .idle:
                self.updateState(.idle)
            case .running:
                self.updateState(.running)
            case .downloading:
                self.updateState(.downloading)
            case .finished:
                self.updateState(.finished)
            case let .error(error):
                self.updateState(.error(error))
            }
        })
        self.context = context
        self.strategyPipe.putNext(strategy)
    }

    private func updateManifests(_ manifests: [StreamSessionManifest]) {
        for manifest in manifests {
            if let index = self.manifests.firstIndex(where: { $0.id == manifest.id }) {
                if audio?.id == manifest.id {
                    setAudioManifest(manifest)
                }
                if video?.id == manifest.id {
                    setVideoManifest(manifest)
                }
                self.manifests[index] = manifest
            } else {
                self.manifests.append(manifest)
            }
        }
        self.manifests = manifests
        manifestsPipe.putNext(manifests)
    }

    private func updateDefaultManifests(_ manifests: [StreamSessionManifest]) {
        if let master = manifests.first(where: { $0.type == .master }), let manifests = findBestChildManifest(in: master) {
            if let audio = manifests.audio {
                setAudioManifest(audio)
            }
            if let video = manifests.video {
                setVideoManifest(video)
            }
        }
    }

    private func updateState(_ state: StreamSessionState) {
        if self.state != state {
            self.state = state
            statePipe.putNext(state)
        }
    }

    // MARK: - Private. Checks

    private func checkManifests() {
        if let audio = audio, !audio.info.ended, audio.info.duration - currentTime <= 5.0 {
            reloadManifests()
        }
        if let video = video, !video.info.ended, video.info.duration - currentTime <= 5.0 {
            reloadManifests()
        }
    }
}

private extension Array {
    // MARK: - Interface

    func safe(at index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
