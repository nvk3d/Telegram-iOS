//
//  StreamMapParseStrategy.swift
//  StreamKit
//
//  Created by Nikita Bondar on 25.10.2024.
//

import Foundation

final class StreamMapParseStrategy: StreamTagParseStrategy {
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

    func parse(_ rows: [String], startTime: Double) throws -> StreamInfo.Map {
        let prefix = "#EXT-X-MAP:"
        guard var row = rows.first, row.hasPrefix(prefix) else { throw ParsingError.dataCorrupted }
        row.removeFirst(prefix.count)

        var byteRange: StreamInfo.ByteRange?
        var uri: String?

        let params = row.parseParams()
        for param in params {
            let components = param.split(separator: "=")
            guard components.count == 2 else { continue }

            switch components[0] {
            case "BYTERANGE":
                let byteRangeString = components[1].replacingOccurrences(of: "\"", with: "")
                let byteRangeComponents = byteRangeString.split(separator: "@")
                if byteRangeComponents.count == 2, let start = Int(byteRangeComponents[1]), let length = Int(byteRangeComponents[0]) {
                    byteRange = StreamInfo.ByteRange(start: start, length: length)
                }
            case "URI":
                uri = String(components[1]).replacingOccurrences(of: "\"", with: "")
            default:
                break
            }
        }

        if let uri = uri {
            return StreamInfo.Map(byteRange: byteRange, startTime: startTime, duration: 0.0, uri: uri)
        }

        throw ParsingError.notEnoughData
    }
}
