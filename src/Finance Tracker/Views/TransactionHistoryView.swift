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
	@State private var filterStartDate: Date?
	@State private var filterEndDate: Date?
	@State private var showingDateFilter = false

	private var isDateFiltered: Bool { filterStartDate != nil || filterEndDate != nil }

	private var filteredTransactions: [Transaction] {
		transactions.filter { txn in
			(filterKind == nil || txn.category?.kind == filterKind)
			&& (filterAccount == nil || txn.paymentAccount === filterAccount)
			&& (filterStartDate == nil || txn.date >= filterStartDate!)
			&& (filterEndDate == nil || txn.date <= filterEndDate!)
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
			.safeAreaInset(edge: .bottom) {
				Color.clear.frame(height: 80)
			}
			.overlay(alignment: .bottomTrailing) {
				Button {
					showingDateFilter = true
				} label: {
					Image(systemName: isDateFiltered ? "calendar.badge.checkmark" : "calendar")
						.font(.title2)
						.foregroundStyle(.white)
						.padding(16)
						.background(isDateFiltered ? Color.green : Color.accentColor)
						.clipShape(Circle())
						.shadow(radius: 4)
				}
				.buttonStyle(.plain)
				.padding()
			}
			.sheet(item: $editingTransaction) { transaction in
				AddTransactionView(editingTransaction: transaction)
			}
			.sheet(isPresented: $showingDateFilter) {
				DateRangePickerView(startDate: $filterStartDate, endDate: $filterEndDate)
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
			let transaction = items[index]
			SyncService.shared.markDeletedRemote(collectionName: "transactions", id: transaction.id)
			modelContext.delete(transaction)
		}
	}
}

struct DateRangePickerView: View {
	@Environment(\.dismiss) private var dismiss
	@Binding var startDate: Date?
	@Binding var endDate: Date?

	@State private var localStart: Date
	@State private var localEnd: Date

	init(startDate: Binding<Date?>, endDate: Binding<Date?>) {
		_startDate = startDate
		_endDate = endDate
		let now = Date.now
		let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
		_localStart = State(initialValue: startDate.wrappedValue ?? monthAgo)
		_localEnd = State(initialValue: endDate.wrappedValue ?? now)
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					DatePicker("From", selection: $localStart, displayedComponents: .date)
					DatePicker("To", selection: $localEnd, in: localStart..., displayedComponents: .date)
				}

				if startDate != nil || endDate != nil {
					Section {
						Button("Clear Filter", role: .destructive) {
							startDate = nil
							endDate = nil
							dismiss()
						}
					}
				}
			}
			.navigationTitle("Date Range")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Apply") {
						startDate = Calendar.current.startOfDay(for: localStart)
						// Include the full end day
						endDate = Calendar.current.date(
							bySettingHour: 23, minute: 59, second: 59, of: localEnd
						)
						dismiss()
					}
				}
			}
		}
		.frame(maxWidth: 400)
	}
}

#Preview {
	TransactionHistoryView()
		.modelContainer(for: [Transaction.self, Category.self, PaymentAccount.self], inMemory: true)
}
