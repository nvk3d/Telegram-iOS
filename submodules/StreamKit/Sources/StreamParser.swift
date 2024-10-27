//
//  StreamParser.swift
//  StreamKit
//
//  Created by Nikita Bondar on 04.10.2024.
//

import Foundation
/*
 #EXT-X-TARGETDURATION - ключ для целевой длительности каждого сегмента,
                        типа длительность каждого сегмента не должна превышать это значение.

 */

/*
 Какие есть форматы ключей?
 
 #EXTM3U8 - без параметров
 #EXT-X-VERSION:n - 1 параметр
 #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs" - много параметров

 */

struct StreamInfo {
    // MARK: - Children

    // #EXT-X-BYTERANGE
    struct ByteRange {
        // MARK: - Properties

        let start: Int?
        let length: Int
    }

    // #EXT-X-MAP
    struct Map {
        // MARK: - Properties

        var id: String {
            if let byteRange = byteRange {
                return "\(byteRange.start ?? 0)_\(byteRange.length)_\(uri)"
            } else {
                return uri
            }
        }

        let byteRange: ByteRange?
        let startTime: Double
        let duration: Double
        let uri: String
    }

    // #EXT-X-MEDIA
    struct Media {
        // MARK: - Children

        enum MediaType: String {
            // MARK: - Cases

            case audio = "AUDIO"
            case closedCaptions = "CLOSED-CAPTIONS"
            case subtitles = "SUBTITLES"
            case video = "VIDEO"
        }

        // MARK: - Properties

        let groupId: String
        let language: String?
        let byDefault: Bool
        let name: String
        let type: MediaType
        let uri: String?
    }

    // #EXTINF
    struct Segment {
        // MARK: - Properties

        var id: String {
            if let byteRange = byteRange {
                return "\(byteRange.start ?? 0)_\(byteRange.length)_\(uri)"
            } else {
                return uri
            }
        }

        let byteRange: ByteRange?
        let duration: Double
        let startTime: Double
        let title: String?
        let uri: String // from next line
    }

    // #EXT-X-STREAM-INF
    struct StreamInfo {
        // MARK: - Children

        struct Resolution {
            // MARK: - Properties

            let value: String
            let width: Int
            let height: Int
        }

        // MARK: - Properties

        let audio: String?
        let bandwidth: Int
        let closedCaptions: String?
        let codecs: [String]?
        let frameRate: Double?
        let resolution: Resolution?
        let subtitles: String?
        let uri: String // from next line
    }

    enum Item {
        // MARK: - Cases

        case map(Map)
        case segment(Segment)

        // MARK: - Properties

        var id: AnyHashable {
            switch self {
            case let .map(map):
                return map.id
            case let .segment(segment):
                return segment.id
            }
        }

        var uri: String {
            switch self {
            case let .map(map):
                return map.uri
            case let .segment(segment):
                return segment.uri
            }
        }
    }

    // MARK: - Properties

    let ended: Bool

    let items: [Item]?
    let media: [Media]?
    let streamInfo: [StreamInfo]?

    let duration: Double

    let targetDuration: Int?
    let version: Int?
}

protocol StreamParser: AnyObject {
    // MARK: - Interface

    func parse(_ contents: String) throws -> StreamInfo
}

final class StreamParserImpl: StreamParser {
    // MARK: - Children

    enum ParsingError: Error {
        // MARK: - Cases

        case formatNotFound
        case notEnoughRowsToParse
    }

    enum Key: String {
        // MARK: - Cases

        case EXTINF = "#EXTINF"
        case EXT_X_BYTERANGE = "#EXT-X-BYTERANGE"
        case EXT_X_ENDLIST = "#EXT-X-ENDLIST"
        case EXT_X_MAP = "#EXT-X-MAP"
        case EXT_X_MEDIA = "#EXT-X-MEDIA"
        case EXT_X_STREAM_INF = "#EXT-X-STREAM-INF"
        case EXT_X_TARGETDURATION = "#EXT-X-TARGETDURATION"
        case EXT_X_VERSION = "#EXT-X-VERSION"
    }

    // MARK: - Properties

    private let emptyParseStrategy: StreamEmptyParseStrategy
    private let mapParseStrategy: StreamMapParseStrategy
    private let mediaParseStrategy: StreamMediaParseStrategy
    private let segmentParseStrategy: StreamSegmentParseStrategy
    private let streamInfoParseStrategy: StreamStreamInfoParseStrategy
    private let targetDurationParseStrategy: StreamTargetDurationParseStrategy
    private let versionParseStrategy: StreamVersionParseStrategy

    // MARK: - Init

    init() {
        emptyParseStrategy = StreamEmptyParseStrategy()
        mapParseStrategy = StreamMapParseStrategy()
        mediaParseStrategy = StreamMediaParseStrategy()
        segmentParseStrategy = StreamSegmentParseStrategy()
        streamInfoParseStrategy = StreamStreamInfoParseStrategy()
        targetDurationParseStrategy = StreamTargetDurationParseStrategy()
        versionParseStrategy = StreamVersionParseStrategy()
    }

    // MARK: - Interface

    func parse(_ contents: String) throws -> StreamInfo {
        let rows = contents.replacingOccurrences(of: "\r", with: "").split(separator: "\n")

        var isFormatFound = false

        var ended = false
        var items: [StreamInfo.Item] = []
        var media: [StreamInfo.Media] = []
        var streamInfo: [StreamInfo.StreamInfo] = []
        var targetDuration: Int?
        var version: Int?

        var duration: Double = 0.0

        var i = 0
        while i < rows.count {
            let row = String(rows[i])

            if !isFormatFound {
                findFormat(row, found: &isFormatFound)
                i += 1
                continue
            }

            if let key = findKey(row) {
                let strategy: StreamTagParseStrategy
                switch key {
                case .EXTINF:
                    strategy = segmentParseStrategy
                case .EXT_X_ENDLIST:
                    strategy = emptyParseStrategy
                case .EXT_X_BYTERANGE:
                    strategy = emptyParseStrategy
                case .EXT_X_MAP:
                    strategy = mapParseStrategy
                case .EXT_X_MEDIA:
                    strategy = mediaParseStrategy
                case .EXT_X_STREAM_INF:
                    strategy = streamInfoParseStrategy
                case .EXT_X_TARGETDURATION:
                    strategy = targetDurationParseStrategy
                case .EXT_X_VERSION:
                    strategy = versionParseStrategy
                }

                var rowsToParse = [row]
                i += 1
                while i < rows.count {
                    let row = String(rows[i])
                    if row.trimmingCharacters(in: .whitespaces).isEmpty {
                        i += 1
                        continue
                    }
                    if strategy.canAccept(row) {
                        rowsToParse.append(row)
                        i += 1
                        continue
                    }
                    break
                }

                switch key {
                case .EXTINF:
                    let segment = try segmentParseStrategy.parse(rowsToParse, startTime: duration)
                    items.append(.segment(segment))
                    duration += segment.duration
                case .EXT_X_ENDLIST:
                    ended = true
                case .EXT_X_BYTERANGE:
                    assertionFailure("byterange must be in stream inf")
                case .EXT_X_MAP:
                    items.append(.map(try mapParseStrategy.parse(rowsToParse, startTime: duration)))
                case .EXT_X_MEDIA:
                    media.append(try mediaParseStrategy.parse(rowsToParse))
                case .EXT_X_STREAM_INF:
                    streamInfo.append(try streamInfoParseStrategy.parse(rowsToParse))
                case .EXT_X_TARGETDURATION:
                    targetDuration = try targetDurationParseStrategy.parse(rowsToParse)
                case .EXT_X_VERSION:
                    version = try versionParseStrategy.parse(rowsToParse)
                }
            } else {
                i += 1
                print("-- dropping row: \(row)")
            }
        }

        if !isFormatFound {
            throw ParsingError.formatNotFound
        }

        return StreamInfo(
            ended: ended,
            items: items,
            media: media,
            streamInfo: streamInfo,
            duration: duration,
            targetDuration: targetDuration,
            version: version
        )
    }

    // MARK: - Private. Help

    private func findFormat(_ row: String, found: inout Bool) {
        found = row.hasPrefix("#EXTM3U")
    }

    private func findKey(_ row: String) -> Key? {
        if row.hasPrefix("#") {
            var key: String = ""
            var i = row.startIndex
            while i < row.endIndex, row[i] != ":" {
                key.append(row[i])
                i = row.index(after: i)
            }
            return Key(rawValue: key)
        }
        return nil
    }
}
