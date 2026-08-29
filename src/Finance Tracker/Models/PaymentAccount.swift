//
//  PaymentAccountKind.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import Foundation
import SwiftData

enum PaymentAccountKind: String, Codable, CaseIterable {
	case creditCard
	case checking
	case savings
	case cash
	case other

	var displayName: String {
		switch self {
		case .creditCard: return "Credit Card"
		case .checking: return "Checking"
		case .savings: return "Savings"
		case .cash: return "Cash"
		case .other: return "Other"
		}
	}

	var defaultIconSystemName: String {
		switch self {
		case .creditCard: return "creditcard.fill"
		case .checking: return "building.columns.fill"
		case .savings: return "banknote.fill"
		case .cash: return "dollarsign.circle.fill"
		case .other: return "circle.fill"
		}
	}
}

@Model
final class PaymentAccount {
	var id: UUID = UUID()
	var name: String = ""                    // e.g. "Chase Sapphire", "Checking"
	var kind: PaymentAccountKind = PaymentAccountKind.checking
	var last4: String = ""                    // optional, e.g. "4242"
	var iconSystemName: String = "creditcard.fill"
	var updatedAt: Date = Date.now

	@Relationship(deleteRule: .nullify, inverse: \Transaction.paymentAccount)
	var transactions: [Transaction]? = []

	init(
		name: String,
		kind: PaymentAccountKind = .checking,
		last4: String = "",
		iconSystemName: String? = nil
	) {
		self.name = name
		self.kind = kind
		self.last4 = last4
		self.iconSystemName = iconSystemName ?? kind.defaultIconSystemName
	}
}
