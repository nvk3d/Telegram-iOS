//
//  StreamSegmentParseStrategy.swift
//  StreamKit
//
//  Created by Nikita Bondar on 05.10.2024.
//

import Foundation

/*
 // #EXTINF
 struct Segment {
     // MARK: - Properties

     let duration: Double
     let title: String?
     let uri: String // from next line
 }
 */

final class StreamSegmentParseStrategy: StreamTagParseStrategy {
    // MARK: - Children

    enum ParsingError: Error {
        // MARK: - Cases

        case dataCorrupted
        case notEnoughData
    }

    // MARK: - Interface

    func canAccept(_ row: String) -> Bool {
        row.hasPrefix("#EXT-X-BYTERANGE:") || !row.hasPrefix("#EXT")
    }

    func parse(_ rows: [String], startTime: Double) throws -> StreamInfo.Segment {
        let prefix = "#EXTINF:"
        let byteRangePrefix = "#EXT-X-BYTERANGE:"
        guard var firstRow = rows.first, firstRow.hasPrefix(prefix) else { throw ParsingError.dataCorrupted }
        guard let lastRow = rows.last, firstRow != lastRow else { throw ParsingError.notEnoughData }
        firstRow.removeFirst(prefix.count)

        var duration: Double?
        var title: String?

        var byteRange: StreamInfo.ByteRange?
        if var byteRangeRow = rows.first(where: { $0.hasPrefix(byteRangePrefix) }) {
            byteRangeRow.removeFirst(byteRangePrefix.count)
            let components = byteRangeRow.split(separator: "@")
            
            var start: Int?
            var length: Int?
            if !components.isEmpty, let maybeLength = Int(components[0]) {
                length = maybeLength
            }
            if components.count > 1, let maybeStart = Int(components[1]) {
                start = maybeStart
            }
            length.flatMap { byteRange = StreamInfo.ByteRange(start: start, length: $0) }
        }

        let components = firstRow.components(separatedBy: ",")
        if components.isEmpty {
            throw ParsingError.notEnoughData
        }

        duration = Double(components[0])
        if components.count > 1, !components[1].isEmpty {
            title = String(components[1])
        }

        let uri = lastRow
        if let duration = duration, !uri.isEmpty {
            return StreamInfo.Segment(byteRange: byteRange, duration: duration, startTime: startTime, title: title, uri: uri)
        }

        throw ParsingError.notEnoughData
    }
}
