//
//  StreamEmptyParseStrategy.swift
//  StreamKit
//
//  Created by Nikita Bondar on 05.10.2024.
//

import Foundation

final class StreamEmptyParseStrategy: StreamTagParseStrategy {
    // MARK: - Interface

    func canAccept(_ row: String) -> Bool {
        false
    }
}
