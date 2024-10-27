//
//  String+Parsing.swift
//  StreamKit
//
//  Created by Nikita Bondar on 04.10.2024.
//

import Foundation

extension String {
    // MARK: - Interface

    func parseParams() -> [String] {
        var parts: [String] = []
        var currentPart = ""

        var hasQuote = false
        var i = startIndex
        while i < endIndex {
            if self[i] == ",", !hasQuote {
                parts.append(currentPart)
                currentPart = ""

                i = index(after: i)
                continue
            }

            currentPart += String(self[i])

            if self[i] == "\"" {
                hasQuote.toggle()
            }

            i = self.index(after: i)

            if i == endIndex, !currentPart.isEmpty {
                parts.append(currentPart)
                currentPart = ""
            }
        }

        return parts
    }
}
