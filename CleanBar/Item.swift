//
//  Item.swift
//  CleanBar
//
//  Created by Alain Lima on 25/08/2026.
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
