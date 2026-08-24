//
//  AddTransactionView.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import SwiftUI
import SwiftData

struct AddTransactionView: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(\.dismiss) private var dismiss

	@Query(sort: \Category.name) private var categories: [Category]
	@Query(sort: \PaymentAccount.name) private var paymentAccounts: [PaymentAccount]

	/// Pass an existing transaction to edit it; leave nil to create a new one.
	var editingTransaction: Transaction?

	@State private var amountText: String = ""
	@State private var date: Date = .now
	@State private var note: String = ""
	@State private var selectedCategory: Category?
	@State private var selectedAccount: PaymentAccount?
	@State private var isPayment: Bool = false

	private var isEditing: Bool { editingTransaction != nil }

	var body: some View {
		NavigationStack {
			Form {
				Section("Details") {
					TextField("Amount", text: $amountText)
					#if os(iOS)
						.keyboardType(.decimalPad)
					#endif
					DatePicker("Date", selection: $date, displayedComponents: .date)
					TextField("Note", text: $note)
				}

				Section("Paid With") {
					Picker("Account", selection: $selectedAccount) {
						Text("None").tag(nil as PaymentAccount?)
						ForEach(paymentAccounts) { account in
							Text(account.name).tag(account as PaymentAccount?)
						}
					}
					.onChange(of: selectedAccount) { _, newAccount in
						if newAccount?.kind != .creditCard { isPayment = false }
					}
					if paymentAccounts.isEmpty {
						Text("Add a credit card or bank account under Payment Accounts to tag transactions.")
							.font(.footnote)
							.foregroundStyle(.secondary)
					}

					if selectedAccount?.kind == .creditCard {
						Toggle("This Is a Payment", isOn: $isPayment)
						if isPayment {
							Text("Payments reduce this card's balance for the month instead of counting as a purchase.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
					}
				}

				if !isPayment {
					Section("Category") {
						Picker("Category", selection: $selectedCategory) {
							Text("None").tag(nil as Category?)
							ForEach(categories) { category in
								Text(category.name).tag(category as Category?)
							}
						}
					}
				}

				if isEditing {
					Section {
						Button("Delete Transaction", role: .destructive) {
							deleteAndDismiss()
						}
					}
				}
			}
			.navigationTitle(isEditing ? "Edit Transaction" : "Add Transaction")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") { save() }
						.disabled(Double(amountText) == nil)
				}
			}
			.onAppear(perform: loadExistingValues)
		}
	}

	private func loadExistingValues() {
		guard let editingTransaction else { return }
		amountText = String(editingTransaction.amount)
		date = editingTransaction.date
		note = editingTransaction.note
		selectedCategory = editingTransaction.category
		selectedAccount = editingTransaction.paymentAccount
		isPayment = editingTransaction.isPayment
	}

	private func save() {
		guard let amount = Double(amountText) else { return }
		// Payments aren't tied to a budget category even if one was picked
		// before the toggle was switched on.
		let categoryToSave = isPayment ? nil : selectedCategory

		if let editingTransaction {
			editingTransaction.amount = amount
			editingTransaction.date = date
			editingTransaction.note = note
			editingTransaction.category = categoryToSave
			editingTransaction.paymentAccount = selectedAccount
			editingTransaction.isPayment = isPayment
		} else {
			let transaction = Transaction(
				amount: amount,
				date: date,
				note: note,
				source: .manual,
				category: categoryToSave,
				paymentAccount: selectedAccount,
				isPayment: isPayment
			)
			modelContext.insert(transaction)
		}
		dismiss()
	}

	private func deleteAndDismiss() {
		guard let editingTransaction else { return }
		modelContext.delete(editingTransaction)
		dismiss()
	}
}

#Preview {
	AddTransactionView()
		.modelContainer(for: [Transaction.self, Category.self, PaymentAccount.self], inMemory: true)
}
