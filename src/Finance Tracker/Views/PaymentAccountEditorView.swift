//
//  PaymentAccountEditorView.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import SwiftUI
import SwiftData

struct PaymentAccountEditorView: View {
	@Query(sort: \PaymentAccount.name) private var accounts: [PaymentAccount]
	@Environment(\.modelContext) private var modelContext

	@State private var editingAccount: PaymentAccount?
	@State private var showingNewAccount = false

	private var currentMonthRange: (start: Date, end: Date) {
		let calendar = Calendar.current
		let now = Date.now
		let comps = calendar.dateComponents([.year, .month], from: now)
		let start = calendar.date(from: comps) ?? now
		let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? now
		return (start, end)
	}

	/// This month's charges minus payments for a credit card — what you'd
	/// still owe for this month's spending if you paid it off today.
	private func monthlyBalance(for account: PaymentAccount) -> Double {
		let range = currentMonthRange
		let txns = (account.transactions ?? [])
			.filter { $0.date >= range.start && $0.date <= range.end }

		let charges = txns.filter { !$0.isPayment }.reduce(0) { $0 + $1.amount }
		let payments = txns.filter { $0.isPayment }.reduce(0) { $0 + $1.amount }
		return charges - payments
	}

    @ViewBuilder
    private func accountTrailingInfo(for account: PaymentAccount) -> some View {
        if account.kind == .creditCard {
            let balance = monthlyBalance(for: account)
            VStack(alignment: .trailing, spacing: 1) {
                Text(balance, format: .currency(code: "USD"))
                    .font(.subheadline.bold())
                    .foregroundStyle(balance > 0 ? Color.primary : Color.green)
                Text("owed this month")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(account.kind.displayName + (account.last4.isEmpty ? "" : " ••\(account.last4)"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func accountLabel(for account: PaymentAccount) -> some View {
        HStack {
            Label {
                Text(account.name)
            } icon: {
                Image(systemName: account.iconSystemName)
            }
            .foregroundStyle(.primary)
            Spacer()
            accountTrailingInfo(for: account)
        }
    }

	var body: some View {
		NavigationStack {
			List {
				ForEach(accounts) { account in
					Button {
						editingAccount = account
					} label: {
						accountLabel(for: account)
					}
					.swipeActions(edge: .trailing) {
						Button(role: .destructive) {
							if let index = accounts.firstIndex(where: { $0.id == account.id }) {
								delete(IndexSet(integer: index))
							}
						} label: {
							Label("Delete", systemImage: "trash")
						}
					}
				}
			}
			.navigationTitle("Payment Accounts")
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button {
						showingNewAccount = true
					} label: {
						Label("Add Account", systemImage: "plus")
					}
				}
			}
			.sheet(isPresented: $showingNewAccount) {
				PaymentAccountFormView(account: nil)
			}
			.sheet(item: $editingAccount) { account in
				PaymentAccountFormView(account: account)
			}
			.overlay {
				if accounts.isEmpty {
					ContentUnavailableView(
						"No Accounts Yet",
						systemImage: "creditcard",
						description: Text("Add a credit card, checking, or savings account to tag your transactions.")
					)
				}
			}
		}
	}

	private func delete(_ offsets: IndexSet) {
		for index in offsets {
			let account = accounts[index]
			SyncService.shared.markDeletedRemote(collectionName: "paymentAccounts", id: account.id)
			modelContext.delete(account)
		}
	}
}

struct PaymentAccountFormView: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(\.dismiss) private var dismiss

	let account: PaymentAccount?

	@State private var name: String = ""
	@State private var kind: PaymentAccountKind = .creditCard
	@State private var last4: String = ""

	var body: some View {
		NavigationStack {
			Form {
				Section("Details") {
					TextField("Name (e.g. Chase Sapphire)", text: $name)
					Picker("Type", selection: $kind) {
						ForEach(PaymentAccountKind.allCases, id: \.self) { kind in
							Text(kind.displayName).tag(kind)
						}
					}
					if kind == .creditCard || kind == .checking || kind == .savings {
						TextField("Last 4 digits (optional)", text: $last4)
						#if os(iOS)
							.keyboardType(.numberPad)
						#endif
							.onChange(of: last4) { _, newValue in
								last4 = String(newValue.filter(\.isNumber).prefix(4))
							}
					}
				}
				if account != nil {
					Section {
						Button("Delete Account", role: .destructive) {
							deleteAndDismiss()
						}
					}
				}
			}
			.navigationTitle(account == nil ? "New Account" : "Edit Account")
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
			.padding(16)
		}
	}

	private func deleteAndDismiss() {
		guard let account else { return }
		SyncService.shared.markDeletedRemote(collectionName: "paymentAccounts", id: account.id)
		modelContext.delete(account)
		dismiss()
	}

	private func loadExistingValues() {
		guard let account else { return }
		name = account.name
		kind = account.kind
		last4 = account.last4
	}

	private func save() {
		let savedAccount: PaymentAccount
		if let account {
			account.name = name
			account.kind = kind
			account.last4 = last4
			// Only refresh the icon if it was still the default for the old kind,
			// so a custom choice isn't clobbered — kept simple here since accounts
			// don't currently expose custom icon selection.
			account.iconSystemName = kind.defaultIconSystemName
			account.updatedAt = .now
			savedAccount = account
		} else {
			let newAccount = PaymentAccount(name: name, kind: kind, last4: last4)
			modelContext.insert(newAccount)
			savedAccount = newAccount
		}
		SyncService.shared.pushPaymentAccount(savedAccount)
		dismiss()
	}
}

#Preview {
	PaymentAccountEditorView()
		.modelContainer(for: [Transaction.self, Category.self, PaymentAccount.self], inMemory: true)
}

