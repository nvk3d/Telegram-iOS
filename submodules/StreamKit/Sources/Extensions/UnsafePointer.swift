//
//  UnsafePointer.swift
//  StreamKit
//
//  Created by Nikita Bondar on 19.10.2024.
//

import Foundation

extension UnsafePointer {
    // MARK: - Interface
    
    func copy(capacity: Int) -> UnsafePointer {
        let mutablePointer = UnsafeMutablePointer<Pointee>.allocate(capacity: capacity)
        mutablePointer.initialize(from: self, count:capacity)
        return UnsafePointer(mutablePointer)
    }
}
