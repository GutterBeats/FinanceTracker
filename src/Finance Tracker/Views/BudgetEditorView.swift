//
//  BudgetEditorView.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/30/26.
//

import SwiftUI
import SwiftData

struct BudgetEditorView: View {
    @Query(sort: \Budget.startDate, order: .reverse) private var budgets: [Budget]
    @Environment(\.modelContext) private var modelContext

    @State private var showingNewBudget = false
    @State private var editingBudget: Budget?

    var body: some View {
        List {
            ForEach(budgets) { budget in
                Button {
                    editingBudget = budget
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(budget.name)
                            .foregroundStyle(.primary)
                        Text("\(budget.startDate.formatted(date: .abbreviated, time: .omitted)) – \(budget.endDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewBudget = true
                } label: {
                    Label("Add Budget", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewBudget) {
            BudgetFormView(budget: nil)
        }
        .sheet(item: $editingBudget) { budget in
            BudgetFormView(budget: budget)
        }
        .overlay {
            if budgets.isEmpty {
                ContentUnavailableView(
                    "No Budgets Yet",
                    systemImage: "calendar",
                    description: Text("Add a budget to define spending periods for your categories.")
                )
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let budget = budgets[index]
            SyncService.shared.markDeletedRemote(collectionName: "budgets", id: budget.id)
            modelContext.delete(budget)
        }
    }
}

struct BudgetFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let budget: Budget?

    private static var defaultStart: Date {
        let comps = Calendar.current.dateComponents([.year, .month], from: .now)
        return Calendar.current.date(from: comps) ?? .now
    }

    @State private var name: String = ""
    @State private var startDate: Date = defaultStart
    @State private var endDate: Date = Calendar.current.date(
        byAdding: DateComponents(month: 1, second: -1),
        to: defaultStart
    ) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                }
                Section("Period") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
            }
            .navigationTitle(budget == nil ? "New Budget" : "Edit Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            .frame(maxWidth: 400)
        }
    }

    private func loadExistingValues() {
        guard let budget else { return }
        name = budget.name
        startDate = budget.startDate
        endDate = budget.endDate
    }

    private func save() {
        let savedBudget: Budget
        if let budget {
            budget.name = name
            budget.startDate = startDate
            budget.endDate = endDate
            budget.updatedAt = .now
            savedBudget = budget
        } else {
            let newBudget = Budget(name: name, startDate: startDate, endDate: endDate)
            modelContext.insert(newBudget)
            savedBudget = newBudget
        }
        SyncService.shared.pushBudget(savedBudget)
        dismiss()
    }
}

#Preview {
    BudgetEditorView()
        .modelContainer(for: [Transaction.self, Category.self, PaymentAccount.self, Budget.self], inMemory: true)
}
