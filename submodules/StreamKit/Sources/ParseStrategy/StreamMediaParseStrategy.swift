//
//  StreamMediaParseStrategy.swift
//  StreamKit
//
//  Created by Nikita Bondar on 04.10.2024.
//

import Foundation
/*
 struct Media {
     // MARK: - Children

     enum MediaType {
         // MARK: - Cases

         case audio
         case closedCaptions
         case subtitles
         case video
     }

     // MARK: - Properties

     let groupId: String
     let language: String?
     let name: String
     let type: MediaType
     let uri: String?
 }
 */

final class StreamMediaParseStrategy: StreamTagParseStrategy {
    // MARK: - Children

    enum ParsingError: Error {
        // MARK: - Cases

        case dataCorrupted
        case notEnoughData
        case uriIsNil
    }

    // MARK: - Interface

    func canAccept(_ row: String) -> Bool {
        false
    }

    func parse(_ rows: [String]) throws -> StreamInfo.Media {
        let prefix = "#EXT-X-MEDIA:"
        guard var row = rows.first, row.hasPrefix(prefix) else { throw ParsingError.dataCorrupted }
        row.removeFirst(prefix.count)

        var groupId: String?
        var language: String?
        var byDefault: Bool = false
        var name: String?
        var type: StreamInfo.Media.MediaType?
        var uri: String?

        let params = row.parseParams()
        for param in params {
            let components = param.split(separator: "=")
            guard components.count == 2 else { continue }

            switch components[0] {
            case "GROUP-ID":
                groupId = String(components[1]).replacingOccurrences(of: "\"", with: "")
            case "LANGUAGE":
                language = String(components[1]).replacingOccurrences(of: "\"", with: "")
            case "DEFAULT":
                byDefault = String(components[1]) == "YES"
            case "NAME":
                name = String(components[1]).replacingOccurrences(of: "\"", with: "")
            case "TYPE":
                type = StreamInfo.Media.MediaType(rawValue: String(components[1]))
            case "URI":
                uri = String(components[1]).replacingOccurrences(of: "\"", with: "")
            default:
                break
            }
        }

        if let groupId = groupId, let name = name, let type = type {
            if type != .closedCaptions, uri == nil {
                throw ParsingError.uriIsNil
            }
            return StreamInfo.Media(groupId: groupId, language: language, byDefault: byDefault, name: name, type: type, uri: uri)
        }

        throw ParsingError.notEnoughData
    }
}
