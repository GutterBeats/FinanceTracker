//
//  Category.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import Foundation
import SwiftData

enum CategoryKind: String, Codable, CaseIterable {
	case income
	case expense
}

@Model
final class Category {
	var id: UUID = UUID()
	var name: String = ""
	var kind: CategoryKind = CategoryKind.expense
	var monthlyLimit: Double = 0.0          // 0 = no budget set; ignored when isCalculatedRemainder is true
	var colorHex: String = "#4A90D9"
	var iconSystemName: String = "circle.fill"

	/// When true, this category's effective budget is computed as
	/// (total income this month) - (sum of other expense categories' monthlyLimit),
	/// rather than using `monthlyLimit` directly. Only one category should have this set.
	var isCalculatedRemainder: Bool = false

	/// Last modified time, used for last-write-wins conflict resolution when syncing.
	var updatedAt: Date = Date.now

	@Relationship(deleteRule: .nullify, inverse: \Transaction.category)
	var transactions: [Transaction]? = []

	init(
		name: String,
		kind: CategoryKind = .expense,
		monthlyLimit: Double = 0.0,
		colorHex: String = "#4A90D9",
		iconSystemName: String = "circle.fill",
		isCalculatedRemainder: Bool = false
	) {
		self.name = name
		self.kind = kind
		self.monthlyLimit = monthlyLimit
		self.colorHex = colorHex
		self.iconSystemName = iconSystemName
		self.isCalculatedRemainder = isCalculatedRemainder
	}
}
