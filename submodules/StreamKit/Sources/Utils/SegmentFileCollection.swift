//
//  SegmentFileCollection.swift
//  StreamKit
//
//  Created by Nikita Bondar on 25.10.2024.
//

import Foundation

final class SegmentFileCollection {
    // MARK: - Properties

    var first: StreamSegmentFile? {
        files.first
    }

    var last: StreamSegmentFile? {
        files.last
    }

    var count: Int {
        files.count
    }

    var isEmpty: Bool {
        files.isEmpty
    }

    private var ids: Set<AnyHashable> = []
    private var files: [StreamSegmentFile] = []

    // MARK: - Interface

    func contains(_ id: AnyHashable) -> Bool {
        ids.contains(id)
    }

    func append(_ file: StreamSegmentFile) {
        files.append(file)
        ids.insert(file.id)
    }

    @discardableResult
    func remove(at index: Array<StreamSegmentFile>.Index) -> StreamSegmentFile {
        files.remove(at: index)
    }

    func clean() {
        ids = []
        files = []
    }

    func file(at index: Array<StreamSegmentFile>.Index) -> StreamSegmentFile {
        files[index]
    }

    func first(where predicate: (StreamSegmentFile) -> Bool) -> StreamSegmentFile? {
        files.first(where: predicate)
    }

    func firstIndex(where predicate: (StreamSegmentFile) -> Bool) -> Array<StreamSegmentFile>.Index? {
        files.firstIndex(where: predicate)
    }

    func last(where predicate: (StreamSegmentFile) -> Bool) -> StreamSegmentFile? {
        files.last(where: predicate)
    }

    func index(after idx: Array<StreamSegmentFile>.Index) -> Array<StreamSegmentFile>.Index {
        files.index(after: idx)
    }

    func forEach(_ impl: (StreamSegmentFile) -> Void) {
        files.forEach { impl($0) }
    }
}
