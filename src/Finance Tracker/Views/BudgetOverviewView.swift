//
//  BudgetOverviewView.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import SwiftUI
import SwiftData

struct BudgetOverviewView: View {
	@Query(sort: \Category.name) private var categories: [Category]
	@Query(sort: \PaymentAccount.name) private var accounts: [PaymentAccount]
	@Query(sort: \Budget.startDate, order: .reverse) private var budgets: [Budget]
	@State private var showingAddTransaction = false
	@State private var showingAccount = false
	@State private var selectedBudget: Budget? = nil
	@State private var filterAccount: PaymentAccount?

	private var calendar: Calendar { .current }

	private var placement: ToolbarItemPlacement {
		#if os(iOS)
			return .navigationBarLeading
		#else
			return .navigation
		#endif
	}

	private var currentMonthRange: (start: Date, end: Date) {
		let now = Date.now
		let comps = calendar.dateComponents([.year, .month], from: now)
		let start = calendar.date(from: comps) ?? now
		let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? now
		return (start, end)
	}

	private var activePeriod: (start: Date, end: Date) {
		selectedBudget.map { ($0.startDate, $0.endDate) } ?? currentMonthRange
	}

	/// Amount spent/earned in a category within its budget period, respecting the account filter.
	private func spent(for category: Category) -> Double {
		let range = activePeriod
		let txns = category.transactions ?? []
		return txns
			.filter { $0.date >= range.start && $0.date <= range.end }
			.filter { filterAccount == nil || $0.paymentAccount === filterAccount }
			.reduce(0) { $0 + $1.amount }
	}

	/// Total income this month across ALL accounts, regardless of the active filter —
	/// used for the remaining-balance calculation so switching the filter doesn't
	/// change what a fixed budget category is allowed to be.
	private var totalIncomeAllAccounts: Double {
		let range = activePeriod
		return budgetCategories
			.filter { $0.kind == .income }
			.flatMap { $0.transactions ?? [] }
			.filter { $0.date >= range.start && $0.date <= range.end }
			.reduce(0) { $0 + $1.amount }
	}

	private var budgetCategories: [Category] {
		guard let selectedBudget else { return [] }
		return categories.filter { $0.budget.id == selectedBudget.id }
	}

	private var totalIncome: Double {
		budgetCategories
			.filter { $0.kind == .income }
			.reduce(0) { $0 + spent(for: $1) }
	}

	private var totalExpenses: Double {
		budgetCategories
			.filter { $0.kind == .expense }
			.reduce(0) { $0 + spent(for: $1) }
	}

	/// A category's effective budget limit. For a calculated-remainder category
	/// this is this month's income minus every other expense category's limit,
	/// rather than its own (unused) `monthlyLimit`. Always based on all-account
	/// income so the account filter only affects what's *shown as spent*, not the budget itself.
	private func limit(for category: Category) -> Double {
		guard category.isCalculatedRemainder else { return category.monthlyLimit }

		let otherLimits = budgetCategories
			.filter { $0.kind == .expense && $0 !== category }
			.reduce(0) { $0 + $1.monthlyLimit }
		return totalIncomeAllAccounts - otherLimits
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 16) {
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
					}

					GroupBox {
						HStack {
							summaryColumn(title: "Income", amount: totalIncome, color: .green)
							Divider()
							summaryColumn(title: "Expenses", amount: totalExpenses, color: .red)
							Divider()
							summaryColumn(title: "Net", amount: totalIncome - totalExpenses, color: .primary)
						}
						.padding(.vertical, 4)
					} label: {
						if budgets.isEmpty {
							Text("This Month")
						} else {
							Picker("Budget", selection: $selectedBudget) {
								ForEach(budgets) { budget in
									Text(budget.name).tag(budget as Budget?)
								}
							}
							.pickerStyle(.menu)
							.labelsHidden()
						}
					}

					let incomeCategories = budgetCategories.filter { $0.kind == .income }
					if !incomeCategories.isEmpty {
						GroupBox {
							VStack(spacing: 0) {
								ForEach(incomeCategories) { category in
									HStack {
										Label(category.name, systemImage: category.iconSystemName)
										Spacer()
										Text(spent(for: category), format: .currency(code: "USD"))
											.foregroundStyle(.secondary)
									}
									.padding(.vertical, 6)
									if category.id != incomeCategories.last?.id {
										Divider()
									}
								}
							}
						} label: {
							Text("Income")
						}
					}

					let expenseCategories = budgetCategories.filter { $0.kind == .expense }
					if !expenseCategories.isEmpty {
						GroupBox {
							VStack(spacing: 0) {
								ForEach(expenseCategories) { category in
									let spent = spent(for: category)
									let limit = limit(for: category)
									let hasLimit = category.isCalculatedRemainder || limit > 0
									let progress = limit > 0 ? min(spent / limit, 1.0) : 0

									VStack(alignment: .leading, spacing: 6) {
										HStack {
											Label(category.name, systemImage: category.iconSystemName)
											if category.isCalculatedRemainder {
												Text("REMAINING")
													.font(.caption2.bold())
													.foregroundStyle(.secondary)
											}
											Spacer()
											Text(hasLimit
												 ? "\(spent, format: .currency(code: "USD")) / \(limit, format: .currency(code: "USD"))"
												 : "\(spent, format: .currency(code: "USD"))")
												.font(.subheadline)
												.foregroundStyle(limit < 0 ? .red : .secondary)
										}
										if hasLimit && limit > 0 {
											ProgressView(value: progress)
												.tint(progress >= 1.0 ? .red : .accentColor)
										} else if limit < 0 {
											Text("Over-allocated by \(abs(limit), format: .currency(code: "USD")) — other budgets exceed income.")
												.font(.caption2)
												.foregroundStyle(.red)
										}
									}
									.padding(.vertical, 4)

									if category.id != expenseCategories.last?.id {
										Divider()
									}
								}
							}
						} label: {
							Text("Budgets")
						}
					}
				}
				.padding()
			}
			.navigationTitle("Budgets")
			.toolbar {
				ToolbarItem(placement: placement) {
					Menu {
						NavigationLink {
							BudgetEditorView()
						} label: {
							Label("Budgets", systemImage: "calendar")
						}
						NavigationLink {
							CategoryEditorView()
						} label: {
							Label("Categories", systemImage: "tag")
						}
						NavigationLink {
							PaymentAccountEditorView()
						} label: {
							Label("Payment Accounts", systemImage: "creditcard")
						}
						Divider()
						Button {
							showingAccount = true
						} label: {
							Label("Account", systemImage: "person.circle")
						}
					} label: {
						Label("More", systemImage: "ellipsis.circle")
					}
				}
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
				ToolbarItem(placement: .primaryAction) {
					Button {
						showingAddTransaction = true
					} label: {
						Label("Add Transaction", systemImage: "plus")
					}
				}
			}
			.sheet(isPresented: $showingAddTransaction) {
				AddTransactionView()
			}
			.sheet(isPresented: $showingAccount) {
				AccountView()
			}
			.onAppear {
				if selectedBudget == nil {
					selectedBudget = activeBudget(from: budgets)
				}
			}
			.onChange(of: budgets) { _, newBudgets in
				if selectedBudget == nil {
					selectedBudget = activeBudget(from: newBudgets)
				}
			}
			.overlay {
				if budgets.isEmpty {
					ContentUnavailableView(
						"No Budgets Yet",
						systemImage: "calendar",
						description: Text("Create a budget period in the ··· menu to get started.")
					)
				} else if budgetCategories.isEmpty {
					ContentUnavailableView(
						"No Categories",
						systemImage: "chart.pie",
						description: Text("Assign a category to this budget in the Categories editor.")
					)
				}
			}
		}
	}

	private func activeBudget(from list: [Budget]) -> Budget? {
		let today = Date.now
		return list.first(where: { $0.startDate <= today && $0.endDate >= today }) ?? list.first
	}

	private func summaryColumn(title: String, amount: Double, color: Color) -> some View {
		VStack(spacing: 2) {
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(amount, format: .currency(code: "USD"))
				.font(.subheadline.bold())
				.foregroundStyle(color)
		}
		.frame(maxWidth: .infinity)
	}
}

#Preview {
	BudgetOverviewView()
		.modelContainer(for: [Transaction.self, Category.self, PaymentAccount.self, Budget.self], inMemory: true)
}

