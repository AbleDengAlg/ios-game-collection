//
//  Item.swift
//  guessNumber
//
//  Created by Able on 2026/4/19.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
