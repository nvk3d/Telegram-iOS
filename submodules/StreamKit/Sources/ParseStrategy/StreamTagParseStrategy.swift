//
//  StreamTagParseStrategy.swift
//  StreamKit
//
//  Created by Nikita Bondar on 05.10.2024.
//

import Foundation

protocol StreamTagParseStrategy: AnyObject {
    // MARK: - Interface

    func canAccept(_ row: String) -> Bool
}
