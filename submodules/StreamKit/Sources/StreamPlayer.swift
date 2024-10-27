//
//  StreamPlayer.swift
//  StreamKit
//
//  Created by Nikita Bondar on 05.10.2024.
//

import CoreMedia
import SwiftSignalKit
import UIKit

public func makePlayerImpl(queue: Queue) -> StreamPlayer {
    StreamPlayerImpl(queue: queue)
}

public enum StreamPlayerAudio: Equatable {
    // MARK: - Children

    public struct Manifest {
        // MARK: - Properties

        public let id: AnyHashable
        public let name: String
        public let language: String?
        public let byDefault: Bool
    }

    // MARK: - Cases

    case auto
    case manual(Manifest)

    // MARK: - Static. Interface

    public static func == (lhs: StreamPlayerAudio, rhs: StreamPlayerAudio) -> Bool {
        if case .auto = lhs, case .auto = rhs { return true }
        if case let .manual(lm) = lhs, case let .manual(rm) = rhs { return lm.id == rm.id }
        return false
    }
}

public enum StreamPlayerVideo: Equatable {
    // MARK: - Children

    public struct Manifest {
        // MARK: - Children

        public struct Resolution {
            // MARK: - Properties

            public let value: String
            public let width: Int
            public let height: Int
        }

        // MARK: - Properties

        public let id: AnyHashable
        public let bandwidth: Int
        public let resolution: Resolution
    }

    // MARK: - Cases

    case auto
    case manual(Manifest)

    // MARK: - Static. Interface

    public static func == (lhs: StreamPlayerVideo, rhs: StreamPlayerVideo) -> Bool {
        if case .auto = lhs, case .auto = rhs { return true }
        if case let .manual(lm) = lhs, case let .manual(rm) = rhs { return lm.id == rm.id }
        return false
    }
}

public enum StreamPlayerState: Equatable {
    // MARK: - Cases

    case idle
    case playing
    case pausing
    case loading
    case ended
    case error(Error)

    // MARK: - Static. Interface

    public static func == (lhs: StreamPlayerState, rhs: StreamPlayerState) -> Bool {
        if case .idle = lhs, case .idle = rhs { return true }
        if case .playing = lhs, case .playing = rhs { return true }
        if case .pausing = lhs, case .pausing = rhs { return true }
        if case .loading = lhs, case .loading = rhs { return true }
        if case .ended = lhs, case .ended = rhs { return true }
        if case .error = lhs, case .error = rhs { return true }
        return false
    }
}

public protocol StreamPlayer: AnyObject {
    // MARK: - Properties

    var audioUpdated: Signal<(current: StreamPlayerAudio.Manifest?, all: [StreamPlayerAudio.Manifest]), NoError> { get }
    var videoUpdated: Signal<(current: StreamPlayerVideo.Manifest?, all: [StreamPlayerVideo.Manifest]), NoError> { get }

    var bufferUpdated: Signal<CMSampleBuffer, NoError> { get }
    var durationUpdated: Signal<TimeInterval, NoError> { get }

    var stateUpdated: Signal<StreamPlayerState, NoError> { get }

    var hasAudio: Bool { get }
    var hasVideo: Bool { get }

    var rate: Double { get }
    var volume: Double { get }

    var audio: StreamPlayerAudio { get }
    var video: StreamPlayerVideo { get }

    // MARK: - Interface

    func play()
    func pause()
    func set(rate: Double)
    func set(volume: Double)
    func set(audio: StreamPlayerAudio)
    func set(video: StreamPlayerVideo)
    func set(url: URL?)
    func seek(to time: Double)
}

final class StreamPlayerImpl: StreamPlayer {
    // MARK: - Properties

    var audioUpdated: Signal<(current: StreamPlayerAudio.Manifest?, all: [StreamPlayerAudio.Manifest]), NoError> { audioPipe.signal() }
    private let audioPipe: ValuePipe<(current: StreamPlayerAudio.Manifest?, all: [StreamPlayerAudio.Manifest])>

    var videoUpdated: Signal<(current: StreamPlayerVideo.Manifest?, all: [StreamPlayerVideo.Manifest]), NoError> { videoPipe.signal() }
    private let videoPipe: ValuePipe<(current: StreamPlayerVideo.Manifest?, all: [StreamPlayerVideo.Manifest])>

    var bufferUpdated: Signal<CMSampleBuffer, NoError> { bufferPipe.signal() }
    private let bufferPipe: ValuePipe<CMSampleBuffer>

    var durationUpdated: Signal<TimeInterval, NoError> { durationPipe.signal() }
    private let durationPipe: ValuePipe<TimeInterval>
    private var _duration: TimeInterval = 0.0

    var stateUpdated: Signal<StreamPlayerState, NoError> { statePipe.signal() }
    private let statePipe: ValuePipe<StreamPlayerState>
    private var _state: StreamPlayerState = .idle

    var hasAudio: Bool { queue.sync { _hasAudio } }
    private var _hasAudio = false

    var hasVideo: Bool { queue.sync { _hasVideo } }
    private var _hasVideo = false

    var rate: Double { queue.sync { _rate } }
    private var _rate: Double = 1.0

    var volume: Double { queue.sync { _volume } }
    private var _volume: Double = 1.0

    var audio: StreamPlayerAudio { queue.sync { _audio } }
    private var _audio: StreamPlayerAudio = .auto

    var video: StreamPlayerVideo { queue.sync { _video } }
    private var _video: StreamPlayerVideo = .auto

    private var needToPlay = false
    private var needToPlayBeforeResignActive = false

    private var sessionTimeReserve: TimeInterval = 0.0

    private var audioManifest: StreamSessionManifest?
    private var videoManifest: StreamSessionManifest?

    private var audioManifests: [StreamSessionManifest] = []
    private var videoManifests: [StreamSessionManifest] = []

    private var context: StreamPlayerContext?

    private var audioRenderer: StreamAudioRenderer?

    private let session: StreamSession
    private let synchronizer: StreamFrameSynchronizer
    private let queue: Queue

    private var baseURL: URL?
    private var currentFps: CMTime = .zero

    private var timer: SwiftSignalKit.Timer?

    private var disposable = DisposableSet()

    // MARK: - Init

    init(session: URLSession = .shared, queue: Queue) {
        let parser = StreamParserImpl()
        let requester = StreamRequesterImpl(parser: parser, session: session, queue: .concurrentDefaultQueue())

        self.session = StreamSessionImpl(fileManager: .default, requester: requester, session: session, queue: queue)
        self.synchronizer = StreamFrameSynchronizer()
        self.queue = queue

        self.audioPipe = ValuePipe()
        self.videoPipe = ValuePipe()

        self.durationPipe = ValuePipe()
        self.bufferPipe = ValuePipe()

        self.statePipe = ValuePipe()

        let center: NotificationCenter = .default
        center.addObserver(self, selector: #selector(appWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        let center: NotificationCenter = .default
        center.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        center.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)

        queue.sync {
            self.invalidate()
        }
    }

    // MARK: - Interface

    func play() {
        queue.async { [weak self] in
            guard let self else { return }

            self.needToPlay = true
            guard self._state != .ended else { return }

            self.updateAudio()
            self.updateVideo()

            self.updateState(.playing)
        }
    }

    func pause() {
        queue.async { [weak self] in
            guard let self else { return }

            self.needToPlay = false
            guard self._state != .ended else { return }

            self.stopContentUpdates()
            self.updateState(.pausing)
        }
    }

    func set(rate: Double) {
        queue.async { [weak self] in
            guard let self else { return }

            self._rate = rate
            self.startContentUpdatesIfNeeded()
        }
    }

    func set(volume: Double) {
        queue.async { [weak self] in
            guard let self else { return }

            self._volume = volume
            self.audioRenderer?.setVolume(volume)
        }
    }

    func set(audio: StreamPlayerAudio) {
        queue.async { [weak self] in
            guard let self else { return }

            switch audio {
            case .auto:
                self._audio = audio

            case let .manual(manifest):
                if let audioManifest = self.audioManifests.first(where: { $0.id == manifest.id }) {
                    self._audio = audio

                    self.session.reset(for: .audio)
                    self.session.set(audio: audioManifest)

                    self.context?.clean(for: .audio)
                    self.startContentUpdatesIfNeeded()
                }
            }
        }
    }

    func set(video: StreamPlayerVideo) {
        queue.async { [weak self] in
            guard let self else { return }

            switch video {
            case .auto:
                self._video = video

            case let .manual(manifest):
                if let videoManifest = self.videoManifests.first(where: { $0.id == manifest.id }) {
                    self._video = video

                    self.session.reset(for: .video)
                    self.session.set(video: videoManifest)

                    self.sessionTimeReserve = 0.0
                    self.context?.clean(for: .video)

                    self.startContentUpdatesIfNeeded()
                }
            }
        }
    }

    func set(url: URL?) {
        queue.async { [weak self] in
            guard let self else { return }

            self.invalidate()
            self.updateState(.idle)

            self.baseURL = url
            guard let url = url else { return }

            self.disposable = DisposableSet()

            self.beginSession(url: url)
        }
    }

    func seek(to time: Double) {
        queue.async { [weak self] in
            guard let self else { return }

            self.stopContentUpdates()
            self.session.seek(to: time)
        }
    }

    // MARK: - Private. Session

    private func beginSession(url: URL) {
        disposable.add((session.manifestsUpdated |> deliverOn(queue)).start { [weak self] manifests in
            guard let self else { return }
            print("manifests: \(manifests.map { $0.id }), not ended: \(manifests.filter { !$0.info.ended }.count)")

            self.audioManifests = manifests.filter { $0.type == .child(.audio) }
            self.videoManifests = manifests.filter { $0.type == .child(.video) }.sorted { ($0.video?.bandwidth ?? 0) < ($1.video?.bandwidth ?? 0) }

            self._hasAudio = !self.audioManifests.isEmpty
            self._hasVideo = !self.videoManifests.isEmpty

            let audios = self.audioManifests.compactMap { $0.toAudio() }
            self.audioPipe.putNext((current: self.audioManifest?.toAudio(), all: audios))

            let videos = self.videoManifests.compactMap { $0.toVideo() }
            self.videoPipe.putNext((current: self.videoManifest?.toVideo(), all: videos))
        })
        disposable.add((session.reserveTimeUpdated |> deliverOn(queue)).start { [weak self] timeReserve in
            guard let self else { return }

            if self._video == .auto, let video = self.videoManifest {
                if timeReserve < self.sessionTimeReserve, timeReserve < 5.0 {
                    if let currentIndex = self.videoManifests.firstIndex(where: { $0.id == video.id }), currentIndex > 0 {
                        self.session.set(video: self.videoManifests[currentIndex - 1])
                        print("manifest updated: \(self.videoManifests[currentIndex - 1].id)")
                    }
                } else if timeReserve > self.sessionTimeReserve, timeReserve > 15.0 {
                    if let currentIndex = self.videoManifests.firstIndex(where: { $0.id == video.id }), currentIndex < self.videoManifests.count - 1 {
                        self.session.set(video: self.videoManifests[currentIndex + 1])
                        print("manifest updated: \(self.videoManifests[currentIndex + 1].id)")
                    }
                }
            }
            self.sessionTimeReserve = timeReserve
        })
        disposable.add((session.audioUpdated |> deliverOn(queue)).start { [weak self] manifest in
            guard let self else { return }

            self._hasAudio = true
            self.audioManifest = manifest
            if !self._hasVideo {
                self.updateDuration(manifest.info.duration)
            }

            let audios = self.audioManifests.compactMap { $0.toAudio() }
            self.audioPipe.putNext((current: manifest.toAudio(), all: audios))
        })
        disposable.add((session.videoUpdated |> deliverOn(queue)).start { [weak self] manifest in
            guard let self else { return }

            self._hasVideo = true
            self.videoManifest = manifest
            self.updateDuration(manifest.info.duration)

            let videos = self.videoManifests.compactMap { $0.toVideo() }
            self.videoPipe.putNext((current: manifest.toVideo(), all: videos))
        })
        disposable.add((session.stateUpdated |> deliverOn(queue)).start { [weak self] state in
            guard let self else { return }

            switch state {
            case .downloading:
                self.updateState(.loading)
                self.stopContentUpdates()

            case .running:
                if self.needToPlay {
                    self.updateAudio()
                    self.updateVideo()
                }
                self.updateState(self.needToPlay ? .playing : .pausing)

            case .finished:
                if self._state == .loading {
                    if self.needToPlay {
                        self.updateAudio()
                        self.updateVideo()
                    }
                    self.updateState(self.needToPlay ? .playing : .pausing)
                }

            case let .error(error):
                self.stopContentUpdates()
                self.updateState(.error(error))

            default:
                break
            }
        })
        disposable.add((session.seeked |> deliverOn(queue)).start { [weak self] _ in
            guard let self else { return }
            print("session has seeked")

            self.cleanContexts()
            self.startContentUpdatesIfNeeded()

            if !self.needToPlay {
                self.updateState(.pausing)
                self.context?.readFrame(for: .video, completion: { [weak self] frame in
                    guard let self, let frame = frame else { return }

                    self.queue.async { [weak self] in
                        guard let self else { return }
                        
                        self.updateCurrentTime(frame)
                        self.queue.justDispatch { self.checkEnded(frame) }
                        self.bufferPipe.putNext(frame.sampleBuffer)
                    }
                })
            }
        })
        disposable.add((session.headerFileDownloaded |> deliverOn(queue)).start { [weak self] file in
            guard let self else { return }
            self.context?.add(file, for: file.content)
        })
        disposable.add((session.segmentFileDownloaded |> deliverOn(queue)).start { [weak self] file in
            guard let self else { return }
            self.context?.add([file], for: file.content)
        })
        disposable.add((session.strategyUpdated |> deliverOn(queue)).start { [weak self] strategy in
            guard let self else { return }

            switch strategy {
            case .single:
                self.context = StreamPlayerSingleContext()
            case .multiple:
                self.context = StreamPlayerMultipleContext()
            }

            self.context?.fpsUpdated = { [weak self] fps in
                guard let self else { return }

                self.queue.async { [weak self] in
                    guard let self else { return }

                    self.currentFps = fps
                    self.updateVideo()
                }
            }
        })
        session.set(url: url)
    }

    // MARK: - Private. System

    private func checkEnded(_ frame: MediaTrackFrame) {
        assert(queue.isCurrent())

        var ended = false
        switch frame.type {
        case .audio:
            if !_hasVideo, let audio = audioManifest, audio.info.ended, frame.position.seconds + frame.duration.seconds >= audio.info.duration - 0.1 {
                ended = true
            }
        case .video:
            if let video = videoManifest, video.info.ended, frame.position.seconds + frame.duration.seconds >= video.info.duration - 0.1 {
                ended = true
            }
        }

        if ended {
            stopContentUpdates()
            updateState(.ended)
        }
    }

    private func cleanContexts() {
        sessionTimeReserve = 0.0

        context?.clean(for: .audio)
        context?.clean(for: .video)

        synchronizer.clean()
    }

    private func startContentUpdatesIfNeeded() {
        if needToPlay {
            updateAudio()
            updateVideo()

            updateState(.playing)
        }
    }

    private func stopContentUpdates() {
        audioRenderer?.stop()
        audioRenderer?.endRequestingFrames()
        timer?.invalidate()
    }

    private func invalidate() {
        _duration = 0.0
        
        _hasAudio = false
        _hasVideo = false

        context?.clean(for: .audio)
        context?.clean(for: .video)
        context?.fpsUpdated = nil
        context = nil

        audioRenderer?.stop()
        audioRenderer?.endRequestingFrames()
        audioRenderer = nil

        synchronizer.clean()

        session.clean()
        disposable.dispose()

        timer?.invalidate()
    }

    // MARK: - Private. Updates

    private func updateAudio() {
        assert(queue.isCurrent())

        audioRenderer?.stop()
        audioRenderer?.endRequestingFrames()
        audioRenderer = nil

        guard let context = context else { return }

        audioRenderer = StreamAudioRenderer(baseRate: 1.0, soundMuted: false, queue: Queue(), updateRate: {}, audioPaused: {})
        audioRenderer?.stop()
        audioRenderer?.setRate(1.0)
        audioRenderer?.setBaseRate(_rate)
        audioRenderer?.setVolume(_volume)

        audioRenderer?.beginRequestingFrames(queue: queue.queue, takeFrame: { [weak self] in
            guard let self else { return .noFrames }

            let frame = self.synchronizer.frame(for: .audio)
            switch frame {
            case let .frame(frame):
                self.updateCurrentTime(frame)
                self.queue.justDispatch { self.checkEnded(frame) }
                return .frame(frame)

            case .noFrames:
                guard let takenFrame = context.readFrame(for: .audio) else { return .skipFrame }
                self.synchronizer.add(frames: [takenFrame], for: .audio)

                if case let .frame(frame) = self.synchronizer.frame(for: .audio) {
                    print("context audio time: \(frame.position.seconds), end: \(frame.position.seconds + frame.duration.seconds)")
                    self.updateCurrentTime(frame)
                    self.queue.justDispatch { self.checkEnded(frame) }
                    return .frame(frame)
                } else {
                    return .skipFrame
                }

            case .waiting:
                return .skipFrame
            }
        })
    }

    private func updateVideo() {
        assert(queue.isCurrent())

        timer?.invalidate()
        timer = nil

        guard let context = context else { return }

        let timeout = currentFps != .zero ? 1.0 / currentFps.seconds : 1.0 / 24.0
        timer = SwiftSignalKit.Timer(timeout: timeout / _rate, repeat: true, completion: { [weak self] in
            guard let self else { return }

            let frame = self.synchronizer.frame(for: .video)
            switch frame {
            case let .frame(frame):
                self.updateCurrentTime(frame)
                self.queue.justDispatch { self.checkEnded(frame) }
                self.bufferPipe.putNext(frame.sampleBuffer)

            case .noFrames:
                guard let takenFrame = context.readFrame(for: .video) else { break }
                self.synchronizer.add(frames: [takenFrame], for: .video)

                if case let .frame(frame) = self.synchronizer.frame(for: .video) {
                    print("context video time: \(frame.position.seconds), end: \(frame.position.seconds + frame.duration.seconds)")
                    self.updateCurrentTime(frame)
                    self.queue.justDispatch { self.checkEnded(frame) }
                    self.bufferPipe.putNext(frame.sampleBuffer)
                }

            case .waiting:
                break
            }
        }, queue: queue)
        timer?.start()
    }

    private func updateCurrentTime(_ frame: MediaTrackFrame) {
        switch frame.type {
        case .audio:
            if !_hasVideo {
                session.currentTimeUpdated(frame.position.seconds)
            }
        case .video:
            session.currentTimeUpdated(frame.position.seconds)
        }
    }

    private func updateDuration(_ duration: TimeInterval) {
        assert(queue.isCurrent())

        if duration > _duration {
            _duration = duration
            durationPipe.putNext(duration)
        }
    }

    private func updateState(_ state: StreamPlayerState) {
        assert(queue.isCurrent())

        if _state != state {
            _state = state
            statePipe.putNext(state)
        }
    }

    // MARK: - Private. Notifications

    @objc
    private func appWillResignActive(_ notification: Notification) {
        queue.async { [weak self] in
            guard let self else { return }

            self.needToPlayBeforeResignActive = self.needToPlay
            if self._state == .playing || self.needToPlay {
                self.pause()
            }
        }
    }

    @objc
    private func appDidBecomeActive(_ notification: Notification) {
        queue.async { [weak self] in
            guard let self else { return }

            if self.needToPlayBeforeResignActive {
                self.play()
                self.session.appDidBecomeActive()
            }
        }
    }
}

private extension StreamSessionManifest {
    // MARK: - Interface

    func toAudio() -> StreamPlayerAudio.Manifest? {
        audio.flatMap { StreamPlayerAudio.Manifest(id: id, name: $0.name, language: $0.language, byDefault: $0.byDefault) }
    }

    func toVideo() -> StreamPlayerVideo.Manifest? {
        video.flatMap { StreamPlayerVideo.Manifest(id: id, bandwidth: $0.bandwidth, resolution: .init(value: $0.resolution.value, width: $0.resolution.width, height: $0.resolution.height)) }
    }
}
