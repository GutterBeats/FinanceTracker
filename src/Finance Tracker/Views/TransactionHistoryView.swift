//
//  TransactionHistoryView.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import SwiftUI
import SwiftData

struct TransactionHistoryView: View {
	@Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
	@Query(sort: \PaymentAccount.name) private var accounts: [PaymentAccount]
	@Environment(\.modelContext) private var modelContext

	@State private var editingTransaction: Transaction?
	@State private var filterKind: CategoryKind?
	@State private var filterAccount: PaymentAccount?

	private var filteredTransactions: [Transaction] {
		transactions.filter { txn in
			(filterKind == nil || txn.category?.kind == filterKind)
			&& (filterAccount == nil || txn.paymentAccount === filterAccount)
		}
	}

	private var groupedByDay: [(day: Date, items: [Transaction])] {
		let calendar = Calendar.current
		let groups = Dictionary(grouping: filteredTransactions) { txn in
			calendar.startOfDay(for: txn.date)
		}
		return groups
			.map { (day: $0.key, items: $0.value) }
			.sorted { $0.day > $1.day }
	}

	var body: some View {
		NavigationStack {
			List {
				Picker("Filter", selection: $filterKind) {
					Text("All").tag(nil as CategoryKind?)
					Text("Income").tag(CategoryKind.income as CategoryKind?)
					Text("Expenses").tag(CategoryKind.expense as CategoryKind?)
				}
				.pickerStyle(.segmented)
				.listRowSeparator(.hidden)

				if let filterAccount {
					HStack {
						Label(filterAccount.name, systemImage: filterAccount.iconSystemName)
							.font(.caption)
						Spacer()
						Button {
							self.filterAccount = nil
						} label: {
							Image(systemName: "xmark.circle.fill")
						}
						.foregroundStyle(.secondary)
					}
					.listRowSeparator(.hidden)
				}

				ForEach(groupedByDay, id: \.day) { group in
					Section(header: Text(group.day.formatted(date: .abbreviated, time: .omitted))) {
						ForEach(group.items) { transaction in
							transactionRow(transaction)
								.contentShape(Rectangle())
								.onTapGesture { editingTransaction = transaction }
						}
						.onDelete { offsets in
							delete(offsets, from: group.items)
						}
					}
				}
			}
			.navigationTitle("History")
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Menu {
						Button {
							filterAccount = nil
						} label: {
							if filterAccount == nil {
								Label("All Accounts", systemImage: "checkmark")
							} else {
								Text("All Accounts")
							}
						}
						Divider()
						ForEach(accounts) { account in
							Button {
								filterAccount = account
							} label: {
								if filterAccount === account {
									Label(account.name, systemImage: "checkmark")
								} else {
									Text(account.name)
								}
							}
						}
					} label: {
						Label("Filter by Account", systemImage: filterAccount == nil ? "creditcard" : "creditcard.fill")
					}
				}
			}
			.sheet(item: $editingTransaction) { transaction in
				AddTransactionView(editingTransaction: transaction)
			}
			.overlay {
				if filteredTransactions.isEmpty {
					ContentUnavailableView(
						"No Transactions",
						systemImage: "list.bullet.rectangle",
						description: Text("Transactions you add will show up here.")
					)
				}
			}
		}
	}

	private func transactionRow(_ transaction: Transaction) -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 4) {
					if transaction.isPayment {
						Image(systemName: "checkmark.circle.fill")
							.font(.caption)
							.foregroundStyle(.green)
					}
					Text(transaction.isPayment ? "Payment" : (transaction.category?.name ?? "Uncategorized"))
				}
				.font(.body)
				HStack(spacing: 4) {
					if let account = transaction.paymentAccount {
						Image(systemName: account.iconSystemName)
							.font(.caption2)
						Text(account.name)
					}
					if !transaction.note.isEmpty {
						if transaction.paymentAccount != nil { Text("·") }
						Text(transaction.note)
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			}
			Spacer()
			Text("\(transaction.isPayment ? "−" : "")\(transaction.amount, format: .currency(code: "USD"))")
				.foregroundStyle(rowAmountColor(for: transaction))
		}
	}

	private func rowAmountColor(for transaction: Transaction) -> Color {
		if transaction.isPayment { return .green }
		return transaction.category?.kind == .income ? .green : .primary
	}

	private func delete(_ offsets: IndexSet, from items: [Transaction]) {
		for index in offsets {
			modelContext.delete(items[index])
		}
	}
}

#Preview {
	TransactionHistoryView()
		.modelContainer(for: [Transaction.self, Category.self, PaymentAccount.self], inMemory: true)
}
