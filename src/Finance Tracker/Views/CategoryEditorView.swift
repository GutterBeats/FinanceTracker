//
//  CategoryEditorView.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import SwiftUI
import SwiftData

struct CategoryEditorView: View {
	@Query(sort: \Category.name) private var categories: [Category]
	@Environment(\.modelContext) private var modelContext

	@State private var editingCategory: Category?
	@State private var showingNewCategory = false
	@State private var categoryToDelete: Category?

	private var expenseCategories: [Category] {
		categories.filter { $0.kind == .expense }
	}

	private var incomeCategories: [Category] {
		categories.filter { $0.kind == .income }
	}

	private var expenseSectionTitle: String {
		expenseCategories.isEmpty ? "" : "Expense Categories"
	}

	private var incomeSectionTitle: String {
		incomeCategories.isEmpty ? "" : "Income Categories"
	}

	var body: some View {
		NavigationStack {
			List {
				Section(expenseSectionTitle) {
					ForEach(expenseCategories) { category in
						categoryRow(category)
					}
					.onDelete { offsets in
						if let index = offsets.first { categoryToDelete = expenseCategories[index] }
					}
				}

				Section(incomeSectionTitle) {
					ForEach(incomeCategories) { category in
						categoryRow(category)
					}
					.onDelete { offsets in
						if let index = offsets.first { categoryToDelete = incomeCategories[index] }
					}
				}
			}
			.navigationTitle("Categories")
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button {
						showingNewCategory = true
					} label: {
						Label("Add Category", systemImage: "plus")
					}
				}
			}
			.sheet(isPresented: $showingNewCategory) {
				CategoryFormView(category: nil)
			}
			.sheet(item: $editingCategory) { category in
				CategoryFormView(category: category)
			}
			.overlay {
				if categories.isEmpty {
					ContentUnavailableView(
						"No Categories Yet",
						systemImage: "tag",
						description: Text("Add an income or expense category to get started.")
					)
				}
			}
			.confirmationDialog(
				"Delete Category?",
				isPresented: Binding(get: { categoryToDelete != nil }, set: { if !$0 { categoryToDelete = nil } }),
				titleVisibility: .visible
			) {
				Button("Delete", role: .destructive) {
					if let c = categoryToDelete { deleteConfirmed(c) }
					categoryToDelete = nil
				}
			} message: {
				Text("This action cannot be undone.")
			}
		}
	}

	private func categoryRow(_ category: Category) -> some View {
		Button {
			editingCategory = category
		} label: {
			HStack {
				Label(category.name, systemImage: category.iconSystemName)
					.foregroundStyle(.primary)
				Spacer()
				if category.isCalculatedRemainder {
					Text("Remaining balance")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				} else if category.kind == .expense && category.monthlyLimit > 0 {
					Text(category.monthlyLimit, format: .currency(code: "USD"))
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	private func deleteConfirmed(_ category: Category) {
		SyncService.shared.markDeletedRemote(collectionName: "categories", id: category.id)
		modelContext.delete(category)
	}
}

struct CategoryFormView: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(\.dismiss) private var dismiss

	@Query private var allCategories: [Category]

	let category: Category?

	@State private var name: String = ""
	@State private var kind: CategoryKind = .expense
	@State private var monthlyLimitText: String = ""
	@State private var iconSystemName: String = "circle.fill"
	@State private var isCalculatedRemainder: Bool = false
	@Query(sort: \Budget.startDate, order: .reverse) private var budgets: [Budget]
	@State private var selectedBudget: Budget? = nil
	@State private var showingDeleteConfirmation = false

	private let iconOptions = [
		"circle.fill", "cart.fill", "house.fill", "car.fill", "fork.knife",
		"bolt.fill", "heart.fill", "gift.fill", "airplane", "banknote.fill",
		"gamecontroller.fill", "book.fill"
	]

	/// True if some *other* category already claims the remainder slot.
	private var anotherCategoryIsRemainder: Bool {
		allCategories.contains { $0.isCalculatedRemainder && $0 !== category }
	}

	var body: some View {
		NavigationStack {
			Form {
				Section("Details") {
					TextField("Name", text: $name)
					Picker("Type", selection: $kind) {
						Text("Expense").tag(CategoryKind.expense)
						Text("Income").tag(CategoryKind.income)
					}
					.pickerStyle(.segmented)
					.onChange(of: kind) { _, newKind in
						if newKind == .income { isCalculatedRemainder = false }
					}
				}

				if kind == .expense {
					Section {
						Toggle("Use Remaining Balance", isOn: $isCalculatedRemainder)
							.disabled(anotherCategoryIsRemainder)

						if isCalculatedRemainder {
							Text("Budget is calculated automatically as this month's income minus every other category's budget.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						} else if anotherCategoryIsRemainder {
							Text("Another category is already using the remaining balance.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						} else {
							TextField("Limit (0 = no limit)", text: $monthlyLimitText)
							#if os(iOS)
								.keyboardType(.decimalPad)
							#endif
						}
					} header: {
						Text("Budget Limit")
					}

				}

				Section("Budget Period") {
					if budgets.isEmpty {
						Text("No budgets yet — create one in the Budgets editor.")
							.font(.footnote)
							.foregroundStyle(.secondary)
					} else {
						Picker("Period", selection: $selectedBudget) {
							ForEach(budgets) { budget in
								Text(budget.name).tag(budget as Budget?)
							}
						}
					}
				}

				Section("Icon") {
					LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
						ForEach(iconOptions, id: \.self) { icon in
							Image(systemName: icon)
								.font(.title2)
								.foregroundStyle(iconSystemName == icon ? Color.accentColor : .primary)
								.frame(maxWidth: .infinity, minHeight: 36)
								.onTapGesture { iconSystemName = icon }
						}
					}
				}
				if category != nil {
					Section {
						Button("Delete Category", role: .destructive) {
							showingDeleteConfirmation = true
						}
					}
				}
			}
			.navigationTitle(category == nil ? "New Category" : "Edit Category")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") { save() }
						.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedBudget == nil)
				}
			}
			.onAppear(perform: loadExistingValues)
			.confirmationDialog(
				"Delete Category?",
				isPresented: $showingDeleteConfirmation,
				titleVisibility: .visible
			) {
				Button("Delete", role: .destructive) { deleteAndDismiss() }
			} message: {
				Text("This action cannot be undone.")
			}
			.frame(maxWidth: 400)
			.padding(16)
		}
	}

	private func deleteAndDismiss() {
		guard let category else { return }
		SyncService.shared.markDeletedRemote(collectionName: "categories", id: category.id)
		modelContext.delete(category)
		dismiss()
	}

	private func loadExistingValues() {
		if let category {
			name = category.name
			kind = category.kind
			monthlyLimitText = category.monthlyLimit > 0 ? String(category.monthlyLimit) : ""
			iconSystemName = category.iconSystemName
			isCalculatedRemainder = category.isCalculatedRemainder
			selectedBudget = category.budget
		} else {
			selectedBudget = budgets.first
		}
	}

	private func save() {
		guard let budget = selectedBudget else { return }
		let limit = isCalculatedRemainder ? 0.0 : (Double(monthlyLimitText) ?? 0.0)

		let savedCategory: Category
		if let category {
			category.name = name
			category.kind = kind
			category.monthlyLimit = limit
			category.iconSystemName = iconSystemName
			category.isCalculatedRemainder = isCalculatedRemainder
			category.budget = budget
			category.updatedAt = .now
			savedCategory = category
		} else {
			let newCategory = Category(
				name: name,
				kind: kind,
				monthlyLimit: limit,
				iconSystemName: iconSystemName,
				isCalculatedRemainder: isCalculatedRemainder,
				budget: budget
			)
			modelContext.insert(newCategory)
			savedCategory = newCategory
		}
		SyncService.shared.pushCategory(savedCategory)
		dismiss()
	}
}

#Preview {
	CategoryEditorView()
		.modelContainer(for: [Transaction.self, Category.self, Budget.self], inMemory: true)
}
