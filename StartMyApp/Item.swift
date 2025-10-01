//
//  Item.swift
//  StartMyApp
//
//  Created by eevv on 9/30/25.
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
