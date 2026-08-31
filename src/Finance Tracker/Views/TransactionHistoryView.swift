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
	@Query(sort: \Budget.startDate, order: .reverse) private var budgets: [Budget]
	@Environment(\.modelContext) private var modelContext
	@Namespace private var namespace

	@State private var editingTransaction: Transaction?
	@State private var filterKind: CategoryKind?
	@State private var filterAccount: PaymentAccount?
	@State private var filterBudget: Budget?
	@State private var filterStartDate: Date?
	@State private var filterEndDate: Date?
	@State private var showingDateFilter = false
	@State private var transactionToDelete: Transaction?

	private var isFiltered: Bool { filterStartDate != nil || filterEndDate != nil || filterAccount != nil }

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

				ForEach(groupedByDay, id: \.day) { group in
					Section(header: Text(group.day.formatted(date: .abbreviated, time: .omitted))) {
						ForEach(group.items) { transaction in
							transactionRow(transaction)
								.contentShape(Rectangle())
								.onTapGesture { editingTransaction = transaction }
								.matchedTransitionSource(id: "addTransaction", in: namespace)
						}
						.onDelete { offsets in
							if let index = offsets.first {
								transactionToDelete = group.items[index]
							}
						}
					}
				}
			}
			.navigationTitle("Transactions")
			.safeAreaInset(edge: .bottom) {
				Color.clear.frame(height: 80)
			}
			.overlay(alignment: .bottomTrailing) {
				Button {
					showingDateFilter = true
				} label: {
					Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
						.font(.title2)
						.foregroundStyle(.white)
						.padding(16)
						.background(isFiltered ? Color.green : Color.accentColor)
						.clipShape(Circle())
						.shadow(radius: 4)
						.matchedTransitionSource(id: "transactionFilter", in: namespace)
				}
				.buttonStyle(.plain)
				.padding()
			}
			.sheet(item: $editingTransaction) { transaction in
				AddTransactionView(editingTransaction: transaction)
					.navigationTransition(.zoom(sourceID: "addTransaction", in: namespace))
			}
			.sheet(isPresented: $showingDateFilter) {
				TransactionFilterView(
					budgets: budgets,
					accounts: accounts,
					startDate: $filterStartDate,
					endDate: $filterEndDate,
					filterBudget: $filterBudget,
					filterAccount: $filterAccount
				)
				.navigationTransition(.zoom(sourceID: "transactionFilter", in: namespace))
			}
			.confirmationDialog(
				"Delete Transaction?",
				isPresented: Binding(get: { transactionToDelete != nil }, set: { if !$0 { transactionToDelete = nil } }),
				titleVisibility: .visible
			) {
				Button("Delete", role: .destructive) {
					if let t = transactionToDelete {
						SyncService.shared.markDeletedRemote(collectionName: "transactions", id: t.id)
						modelContext.delete(t)
					}
					transactionToDelete = nil
				}
			} message: {
				Text("This action cannot be undone.")
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

}

struct TransactionFilterView: View {
	@Environment(\.dismiss) private var dismiss

	let budgets: [Budget]
	let accounts: [PaymentAccount]

	@Binding var startDate: Date?
	@Binding var endDate: Date?
	@Binding var filterBudget: Budget?
	@Binding var filterAccount: PaymentAccount?

	@State private var localBudget: Budget?
	@State private var localAccount: PaymentAccount?
	@State private var localStart: Date
	@State private var localEnd: Date

	private var isFiltered: Bool {
		startDate != nil || endDate != nil || filterBudget != nil || filterAccount != nil
	}

	init(
		budgets: [Budget],
		accounts: [PaymentAccount],
		startDate: Binding<Date?>,
		endDate: Binding<Date?>,
		filterBudget: Binding<Budget?>,
		filterAccount: Binding<PaymentAccount?>
	) {
		self.budgets = budgets
		self.accounts = accounts
		_startDate = startDate
		_endDate = endDate
		_filterBudget = filterBudget
		_filterAccount = filterAccount
		_localBudget = State(initialValue: filterBudget.wrappedValue)
		_localAccount = State(initialValue: filterAccount.wrappedValue)
		let now = Date.now
		let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
		_localStart = State(initialValue: startDate.wrappedValue ?? monthAgo)
		_localEnd = State(initialValue: endDate.wrappedValue ?? now)
	}

	var body: some View {
		NavigationStack {
			Form {
				if !budgets.isEmpty {
					Section("Budget Period") {
						Picker("Budget", selection: $localBudget) {
							Text("None").tag(nil as Budget?)
							ForEach(budgets) { budget in
								Text(budget.name).tag(budget as Budget?)
							}
						}
						.onChange(of: localBudget) { _, budget in
							if let budget {
								localStart = budget.startDate
								localEnd = budget.endDate
							}
						}
					}
				}

				Section("Date Range") {
					DatePicker("From", selection: $localStart, displayedComponents: .date)
						.disabled(localBudget != nil)
					DatePicker("To", selection: $localEnd, in: localStart..., displayedComponents: .date)
						.disabled(localBudget != nil)
				}

				if !accounts.isEmpty {
					Section("Account") {
						Picker("Account", selection: $localAccount) {
							Text("All Accounts").tag(nil as PaymentAccount?)
							ForEach(accounts) { account in
								Text(account.name).tag(account as PaymentAccount?)
							}
						}
					}
				}

				if isFiltered {
					Section {
						Button("Clear All Filters", role: .destructive) {
							startDate = nil
							endDate = nil
							filterBudget = nil
							filterAccount = nil
							dismiss()
						}
					}
				}
			}
			.navigationTitle("Filters")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Apply") {
						filterBudget = localBudget
						filterAccount = localAccount
						if let budget = localBudget {
							startDate = Calendar.current.startOfDay(for: budget.startDate)
							endDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: budget.endDate)
						} else {
							startDate = Calendar.current.startOfDay(for: localStart)
							endDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: localEnd)
						}
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
		.modelContainer(for: [Transaction.self, Category.self, PaymentAccount.self, Budget.self], inMemory: true)
}
