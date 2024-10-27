//
//  StreamSessionContext.swift
//  StreamKit
//
//  Created by Nikita Bondar on 25.10.2024.
//

import Foundation
import SwiftSignalKit

enum StreamSessionContextState: Equatable {
    // MARK: - Cases

    case idle
    case running
    case downloading
    case finished
    case error(Error)

    // MARK: - Static. Interface

    static func == (lhs: StreamSessionContextState, rhs: StreamSessionContextState) -> Bool {
        if case .idle = lhs, case .idle = rhs { return true }
        if case .running = lhs, case .running = rhs { return true }
        if case .downloading = lhs, case .downloading = rhs { return true }
        if case .finished = lhs, case .finished = rhs { return true }
        if case .error = lhs, case .error = rhs { return true }
        return false
    }
}

protocol StreamSessionContext: AnyObject {
    // MARK: - Properties

    var seeked: Signal<Void, NoError> { get }
    var reserveTimeUpdated: Signal<Double, NoError> { get }
    var headerFileDownloaded: Signal<StreamHeaderFile, NoError> { get }
    var segmentFileDownloaded: Signal<StreamSegmentFile, NoError> { get }
    var stateUpdated: Signal<StreamSessionContextState, NoError> { get }

    // MARK: - Interface

    func currentTimeUpdated(_ time: TimeInterval)
    func seek(to time: TimeInterval)

    func set(manifest: StreamSessionManifest, for content: StreamSessionManifestContent)

    func reset(for content: StreamSessionManifestContent)
    func clean()
}
