//
//  StreamStreamInfoParseStrategy.swift
//  StreamKit
//
//  Created by Nikita Bondar on 05.10.2024.
//

import Foundation

/*
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
     let codecs: [String]
     let frameRate: Double?
     let resolution: Resolution?
     let subtitles: String?
     let uri: String // from next line
 }
 */

final class StreamStreamInfoParseStrategy: StreamTagParseStrategy {
    // MARK: - Children

    enum ParsingError: Error {
        // MARK: - Cases

        case dataCorrupted
        case notEnoughData
        case uriIsNil
    }
    
    // MARK: - Interface

    func canAccept(_ row: String) -> Bool {
        !row.hasPrefix("#EXT")
    }

    func parse(_ rows: [String]) throws -> StreamInfo.StreamInfo {
        let prefix = "#EXT-X-STREAM-INF:"
        guard var firstRow = rows.first, firstRow.hasPrefix(prefix) else { throw ParsingError.dataCorrupted }
        guard let secondRow = rows.last, firstRow != secondRow else { throw ParsingError.notEnoughData }
        firstRow.removeFirst(prefix.count)

        var audio: String?
        var bandwidth: Int?
        var closedCaptions: String?
        var codecs: [String]?
        var frameRate: Double?
        var resolution: StreamInfo.StreamInfo.Resolution?
        var subtitles: String?

        let params = firstRow.parseParams()
        for param in params {
            let components = param.split(separator: "=")
            guard components.count == 2 else { continue }

            switch components[0] {
            case "AUDIO":
                audio = String(components[1]).replacingOccurrences(of: "\"", with: "")
            case "BANDWIDTH":
                bandwidth = Int(components[1])
            case "CLOSED-CAPTIONS":
                closedCaptions = String(components[1]).replacingOccurrences(of: "\"", with: "")
            case "CODECS":
                codecs = components[1].replacingOccurrences(of: "\"", with: "").split(separator: ",").map { String($0) }
            case "FRAME-RATE":
                frameRate = Double(components[1])
            case "RESOLUTION":
                let splitted = components[1].split(separator: "x")
                guard splitted.count == 2, let width = Int(splitted[0]), let height = Int(splitted[1]) else { continue }
                resolution = StreamInfo.StreamInfo.Resolution(value: String(components[1]), width: width, height: height)
            case "SUBTITLES":
                subtitles = String(components[1]).replacingOccurrences(of: "\"", with: "")
            default:
                break
            }
        }

        let uri = rows[1]
        if let bandwidth = bandwidth, !uri.isEmpty {
            return StreamInfo.StreamInfo(
                audio: audio,
                bandwidth: bandwidth,
                closedCaptions: closedCaptions,
                codecs: codecs,
                frameRate: frameRate,
                resolution: resolution,
                subtitles: subtitles,
                uri: uri
            )
        }

        throw ParsingError.notEnoughData
    }
}
