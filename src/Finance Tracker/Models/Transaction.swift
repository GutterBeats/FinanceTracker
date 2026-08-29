//
//  Transaction.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import Foundation
import SwiftData

enum TransactionSource: String, Codable, CaseIterable {
	case manual
	case imported
}

@Model
final class Transaction {
	var id: UUID = UUID()
	var amount: Double = 0.0
	var date: Date = Date.now
	var note: String = ""
	var source: TransactionSource = TransactionSource.manual

	/// True when this transaction is a payment toward an account's balance
	/// (e.g. paying off a credit card) rather than a purchase. Payments are
	/// excluded from category budget totals and instead reduce the balance
	/// shown for the associated account.
	var isPayment: Bool = false

	var updatedAt: Date = Date.now

	var category: Category?
	var paymentAccount: PaymentAccount?

	init(
		amount: Double,
		date: Date = .now,
		note: String = "",
		source: TransactionSource = .manual,
		category: Category? = nil,
		paymentAccount: PaymentAccount? = nil,
		isPayment: Bool = false
	) {
		self.amount = amount
		self.date = date
		self.note = note
		self.source = source
		self.category = category
		self.paymentAccount = paymentAccount
		self.isPayment = isPayment
	}
}
