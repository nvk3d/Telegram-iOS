//
//  StreamRequester.swift
//  StreamKit
//
//  Created by Nikita Bondar on 05.10.2024.
//

import Foundation
import SwiftSignalKit

enum StreamRequesterError: Error {
    // MARK: - Cases

    case cancelled
    case some(Error)
    case unknown
}

protocol StreamRequester: AnyObject {
    // MARK: - Interface

    func request(_ url: URL) -> Signal<StreamInfo, StreamRequesterError>
    func cancel()
}

final class StreamRequesterImpl: StreamRequester {
    // MARK: - Children

    private final class Request {
        // MARK: - Properties

        let id: String
        let subscriber: Subscriber<StreamInfo, StreamRequesterError>
        let url: URL

        weak var task: URLSessionTask?

        // MARK: - Init

        init(id: String, subscriber: Subscriber<StreamInfo, StreamRequesterError>, url: URL) {
            self.id = id
            self.subscriber = subscriber
            self.url = url
        }
    }

    private final class State {
        // MARK: - Properties

        var inProgressRequests: [Request] = []
        var waitingRequests: [Request] = []
    }

    // MARK: - Properties

    private let maxRequestsCount: Int
    private let parser: StreamParser
    private let session: URLSession
    private let queue: Queue

    private let state: Atomic<State>

    // MARK: - Init

    init(maxRequestsCount: Int = 4, parser: StreamParser, session: URLSession, queue: Queue) {
        self.maxRequestsCount = maxRequestsCount
        self.parser = parser
        self.session = session
        self.queue = queue

        state = Atomic(value: State())
    }

    // MARK: - Interface

    func request(_ url: URL) -> Signal<StreamInfo, StreamRequesterError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }

            let id = UUID().uuidString
            _ = self.state.modify { state in
                state.waitingRequests += [Request(id: id, subscriber: subscriber, url: url)]
                return state
            }
            self.performNext()

            return ActionDisposable { [weak self] in
                guard let self else { return }

                _ = self.state.modify { state in
                    if let index = state.inProgressRequests.firstIndex(where: { $0.id == id }) {
                        let request = state.inProgressRequests[index]
                        request.task?.cancel()
                        state.inProgressRequests.remove(at: index)
                    }
                    return state
                }
            }
        } |> runOn(queue)
    }

    func cancel() {
        _ = state.modify { state in
            for request in state.inProgressRequests {
                request.task?.cancel()
                request.subscriber.putError(.cancelled)
            }
            state.inProgressRequests = []

            for request in state.waitingRequests {
                request.subscriber.putError(.cancelled)
            }
            state.waitingRequests = []

            return state
        }
    }

    // MARK: - Private. Help

    private func performNext() {
        _ = state.modify { state in
            if state.inProgressRequests.count < maxRequestsCount, !state.waitingRequests.isEmpty {
                let request = state.waitingRequests.removeFirst()

                let urlRequest = URLRequest(url: request.url)
                let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
                    guard let self else { return }

                    self.queue.async { [weak self] in
                        guard let self else { return }

                        if let data = data, let contents = String(data: data, encoding: .utf8) {
                            do {
                                let streamInfo = try self.parser.parse(contents)
                                request.subscriber.putNext(streamInfo)
                                request.subscriber.putCompletion()
                            } catch {
                                request.subscriber.putError(.some(error))
                            }
                        } else if let error = error {
                            request.subscriber.putError(.some(error))
                        } else {
                            request.subscriber.putError(.unknown)
                        }

                        _ = self.state.modify { state in
                            if let index = state.inProgressRequests.firstIndex(where: { $0.id == request.id }) {
                                state.inProgressRequests.remove(at: index)
                            }
                            return state
                        }

                        self.performNext()

                        // maybe make retry policy or smth?
                        // need handling of errors like 403
                    }
                }
                request.task = task

                state.inProgressRequests.append(request)
                task.resume()
            }
            print("in progress count: \(state.inProgressRequests.count), waiting count: \(state.waitingRequests.count)")
            return state
        }
    }
}
