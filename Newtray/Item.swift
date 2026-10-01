//
//  Item.swift
//  Newtray
//
//  Created by Moizes Sousa on 01/10/26.
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
