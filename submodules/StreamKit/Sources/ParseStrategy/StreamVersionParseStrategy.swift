//
//  StreamVersionParseStrategy.swift
//  StreamKit
//
//  Created by Nikita Bondar on 05.10.2024.
//

import Foundation

final class StreamVersionParseStrategy: StreamTagParseStrategy {
    // MARK: - Children

    enum ParsingError: Error {
        // MARK: - Cases

        case dataCorrupted
        case notEnoughData
    }

    // MARK: - Interface

    func canAccept(_ row: String) -> Bool {
        false
    }

    func parse(_ rows: [String]) throws -> Int {
        let prefix = "#EXT-X-VERSION:"
        guard var row = rows.first, row.hasPrefix(prefix) else { throw ParsingError.dataCorrupted }
        row.removeFirst(prefix.count)

        if let version = Int(row) {
            return version
        }

        throw ParsingError.notEnoughData
    }
}
