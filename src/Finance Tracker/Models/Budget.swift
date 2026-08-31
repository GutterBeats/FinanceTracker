//
//  Budget.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/30/26.
//

import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Category.budget)
    var categories: [Category]? = []

    init(name: String, startDate: Date, endDate: Date) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
    }
}
