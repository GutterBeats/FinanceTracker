//
//  SyncService.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/24/26.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Syncs Category, PaymentAccount, and Transaction between this device's local
/// SwiftData store and Firestore, so multiple devices signed into the same
/// Firebase account stay in sync without CloudKit.
///
/// Strategy: every record carries a stable `id: UUID` and an `updatedAt` date.
/// - Pushing writes the full record to /users/{uid}/{collection}/{id}.
/// - Deleting sets a `deleted: true` tombstone rather than removing the doc,
///   so other devices can detect and mirror the deletion.
/// - Listening merges remote changes into the local store, only overwriting a
///   local record when the remote `updatedAt` is newer (last-write-wins).
@MainActor
final class SyncService: ObservableObject {
	static let shared = SyncService()
	private init() {}

	private let db = Firestore.firestore()
	private var listeners: [ListenerRegistration] = []

	@Published var isListening = false
	@Published var lastSyncError: String?

	private var userID: String? { Auth.auth().currentUser?.uid }

	private func collection(_ name: String) -> CollectionReference? {
		guard let userID else { return nil }
		return db.collection("users").document(userID).collection(name)
	}

	/// Firestore completion closures aren't guaranteed to run on the main
	/// actor, so this is callable from anywhere and hops over itself before
	/// touching @Published state.
	nonisolated private func reportError(_ error: Error?) {
		guard let error else { return }
		Task { @MainActor in
			self.lastSyncError = error.localizedDescription
		}
	}

	// MARK: - Push (local -> remote)

	func pushCategory(_ category: Category) {
		guard let ref = collection("categories")?.document(category.id.uuidString) else { return }
		ref.setData([
			"id": category.id.uuidString,
			"name": category.name,
			"kind": category.kind.rawValue,
			"monthlyLimit": category.monthlyLimit,
			"colorHex": category.colorHex,
			"iconSystemName": category.iconSystemName,
			"isCalculatedRemainder": category.isCalculatedRemainder,
			"budgetID": category.budget.id.uuidString,
			"updatedAt": Timestamp(date: category.updatedAt),
			"deleted": false,
		], merge: true) { [weak self] error in
			self?.reportError(error)
		}
	}

	func pushPaymentAccount(_ account: PaymentAccount) {
		guard let ref = collection("paymentAccounts")?.document(account.id.uuidString) else { return }
		ref.setData([
			"id": account.id.uuidString,
			"name": account.name,
			"kind": account.kind.rawValue,
			"last4": account.last4,
			"iconSystemName": account.iconSystemName,
			"updatedAt": Timestamp(date: account.updatedAt),
			"deleted": false,
		], merge: true) { [weak self] error in
			self?.reportError(error)
		}
	}

	func pushBudget(_ budget: Budget) {
		guard let ref = collection("budgets")?.document(budget.id.uuidString) else { return }
		ref.setData([
			"id": budget.id.uuidString,
			"name": budget.name,
			"startDate": Timestamp(date: budget.startDate),
			"endDate": Timestamp(date: budget.endDate),
			"updatedAt": Timestamp(date: budget.updatedAt),
			"deleted": false,
		], merge: true) { [weak self] error in
			self?.reportError(error)
		}
	}

	func pushTransaction(_ transaction: Transaction) {
		guard let ref = collection("transactions")?.document(transaction.id.uuidString) else { return }
		var data: [String: Any] = [
			"id": transaction.id.uuidString,
			"amount": transaction.amount,
			"date": Timestamp(date: transaction.date),
			"note": transaction.note,
			"source": transaction.source.rawValue,
			"isPayment": transaction.isPayment,
			"updatedAt": Timestamp(date: transaction.updatedAt),
			"deleted": false,
		]
		data["categoryID"] = transaction.category?.id.uuidString
		data["paymentAccountID"] = transaction.paymentAccount?.id.uuidString

		ref.setData(data, merge: true) { [weak self] error in
			self?.reportError(error)
		}
	}

	/// Call before locally deleting a record so other devices learn about the deletion.
	func markDeletedRemote(collectionName: String, id: UUID) {
		collection(collectionName)?.document(id.uuidString).setData([
			"deleted": true,
			"updatedAt": Timestamp(date: .now),
		], merge: true)
	}

	/// Uploads everything currently in the local store. Call once right after
	/// sign-in so pre-existing local data reaches Firestore (and, from there,
	/// any other signed-in device).
	func pushAllLocalData(context: ModelContext) {
		if let budgets = try? context.fetch(FetchDescriptor<Budget>()) {
			budgets.forEach(pushBudget)
		}
		if let categories = try? context.fetch(FetchDescriptor<Category>()) {
			categories.forEach(pushCategory)
		}
		if let accounts = try? context.fetch(FetchDescriptor<PaymentAccount>()) {
			accounts.forEach(pushPaymentAccount)
		}
		if let transactions = try? context.fetch(FetchDescriptor<Transaction>()) {
			transactions.forEach(pushTransaction)
		}
	}

	// MARK: - Pull (remote -> local)

	func startListening(context: ModelContext) {
		stopListening()
		guard userID != nil else { return }
		isListening = true

		if let l = collection("budgets")?.addSnapshotListener({ [weak self] snap, _ in
			Task { @MainActor in
				self?.mergeBudgets(snap, into: context)
			}
		}) { listeners.append(l) }

		if let l = collection("categories")?.addSnapshotListener({ [weak self] snap, _ in
			Task { @MainActor in
				self?.mergeCategories(snap, into: context)
			}
		}) { listeners.append(l) }

		if let l = collection("paymentAccounts")?.addSnapshotListener({ [weak self] snap, _ in
			Task { @MainActor in
				self?.mergePaymentAccounts(snap, into: context)
			}
		}) { listeners.append(l) }

		if let l = collection("transactions")?.addSnapshotListener({ [weak self] snap, _ in
			Task { @MainActor in
				self?.mergeTransactions(snap, into: context)
			}
		}) { listeners.append(l) }
	}

	func stopListening() {
		listeners.forEach { $0.remove() }
		listeners.removeAll()
		isListening = false
	}

	private func mergeCategories(_ snapshot: QuerySnapshot?, into context: ModelContext) {
		guard let docs = snapshot?.documents else { return }
		for doc in docs {
			let data = doc.data()
			guard let idString = data["id"] as? String, let id = UUID(uuidString: idString) else { continue }
			let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
			let deleted = data["deleted"] as? Bool ?? false

			let existing = try? context.fetch(
				FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
			).first

			if deleted {
				if let existing { context.delete(existing) }
				continue
			}
			if let existing, existing.updatedAt >= remoteUpdatedAt {
				continue // local copy is same age or newer; nothing to do
			}

			let kind = CategoryKind(rawValue: data["kind"] as? String ?? "") ?? .expense
			let resolvedBudget: Budget? = (data["budgetID"] as? String).flatMap { idStr in
				guard let bid = UUID(uuidString: idStr) else { return nil }
				return try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.id == bid })).first
			}
			guard let resolvedBudget else { continue }
			if let existing {
				existing.name = data["name"] as? String ?? existing.name
				existing.kind = kind
				existing.monthlyLimit = data["monthlyLimit"] as? Double ?? existing.monthlyLimit
				existing.colorHex = data["colorHex"] as? String ?? existing.colorHex
				existing.iconSystemName = data["iconSystemName"] as? String ?? existing.iconSystemName
				existing.isCalculatedRemainder = data["isCalculatedRemainder"] as? Bool ?? existing.isCalculatedRemainder
				existing.budget = resolvedBudget
				existing.updatedAt = remoteUpdatedAt
			} else {
				let new = Category(
					name: data["name"] as? String ?? "",
					kind: kind,
					monthlyLimit: data["monthlyLimit"] as? Double ?? 0,
					colorHex: data["colorHex"] as? String ?? "#4A90D9",
					iconSystemName: data["iconSystemName"] as? String ?? "circle.fill",
					isCalculatedRemainder: data["isCalculatedRemainder"] as? Bool ?? false,
					budget: resolvedBudget
				)
				new.id = id
				new.updatedAt = remoteUpdatedAt
				context.insert(new)
			}
		}
	}

	private func mergeBudgets(_ snapshot: QuerySnapshot?, into context: ModelContext) {
		guard let docs = snapshot?.documents else { return }
		for doc in docs {
			let data = doc.data()
			guard let idString = data["id"] as? String, let id = UUID(uuidString: idString) else { continue }
			let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
			let deleted = data["deleted"] as? Bool ?? false

			let existing = try? context.fetch(
				FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })
			).first

			if deleted {
				if let existing { context.delete(existing) }
				continue
			}
			if let existing, existing.updatedAt >= remoteUpdatedAt {
				continue
			}

			if let existing {
				existing.name = data["name"] as? String ?? existing.name
				existing.startDate = (data["startDate"] as? Timestamp)?.dateValue() ?? existing.startDate
				existing.endDate = (data["endDate"] as? Timestamp)?.dateValue() ?? existing.endDate
				existing.updatedAt = remoteUpdatedAt
			} else {
				let new = Budget(
					name: data["name"] as? String ?? "",
					startDate: (data["startDate"] as? Timestamp)?.dateValue() ?? .now,
					endDate: (data["endDate"] as? Timestamp)?.dateValue() ?? .now
				)
				new.id = id
				new.updatedAt = remoteUpdatedAt
				context.insert(new)
			}
		}
	}

	private func mergePaymentAccounts(_ snapshot: QuerySnapshot?, into context: ModelContext) {
		guard let docs = snapshot?.documents else { return }
		for doc in docs {
			let data = doc.data()
			guard let idString = data["id"] as? String, let id = UUID(uuidString: idString) else { continue }
			let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
			let deleted = data["deleted"] as? Bool ?? false

			let existing = try? context.fetch(
				FetchDescriptor<PaymentAccount>(predicate: #Predicate { $0.id == id })
			).first

			if deleted {
				if let existing { context.delete(existing) }
				continue
			}
			if let existing, existing.updatedAt >= remoteUpdatedAt {
				continue
			}

			let kind = PaymentAccountKind(rawValue: data["kind"] as? String ?? "") ?? .checking
			if let existing {
				existing.name = data["name"] as? String ?? existing.name
				existing.kind = kind
				existing.last4 = data["last4"] as? String ?? existing.last4
				existing.iconSystemName = data["iconSystemName"] as? String ?? existing.iconSystemName
				existing.updatedAt = remoteUpdatedAt
			} else {
				let new = PaymentAccount(
					name: data["name"] as? String ?? "",
					kind: kind,
					last4: data["last4"] as? String ?? "",
					iconSystemName: data["iconSystemName"] as? String
				)
				new.id = id
				new.updatedAt = remoteUpdatedAt
				context.insert(new)
			}
		}
	}

	private func mergeTransactions(_ snapshot: QuerySnapshot?, into context: ModelContext) {
		guard let docs = snapshot?.documents else { return }
		for doc in docs {
			let data = doc.data()
			guard let idString = data["id"] as? String, let id = UUID(uuidString: idString) else { continue }
			let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
			let deleted = data["deleted"] as? Bool ?? false

			let existing = try? context.fetch(
				FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
			).first

			if deleted {
				if let existing { context.delete(existing) }
				continue
			}
			if let existing, existing.updatedAt >= remoteUpdatedAt {
				continue
			}

			let categoryID = (data["categoryID"] as? String).flatMap(UUID.init)
			let accountID = (data["paymentAccountID"] as? String).flatMap(UUID.init)
			let resolvedCategory = categoryID.flatMap { cid in
				try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == cid })).first
			}
			let resolvedAccount = accountID.flatMap { aid in
				try? context.fetch(FetchDescriptor<PaymentAccount>(predicate: #Predicate { $0.id == aid })).first
			}
			let source = TransactionSource(rawValue: data["source"] as? String ?? "") ?? .manual

			if let existing {
				existing.amount = data["amount"] as? Double ?? existing.amount
				existing.date = (data["date"] as? Timestamp)?.dateValue() ?? existing.date
				existing.note = data["note"] as? String ?? existing.note
				existing.source = source
				existing.isPayment = data["isPayment"] as? Bool ?? existing.isPayment
				existing.category = resolvedCategory
				existing.paymentAccount = resolvedAccount
				existing.updatedAt = remoteUpdatedAt
			} else {
				let new = Transaction(
					amount: data["amount"] as? Double ?? 0,
					date: (data["date"] as? Timestamp)?.dateValue() ?? .now,
					note: data["note"] as? String ?? "",
					source: source,
					category: resolvedCategory,
					paymentAccount: resolvedAccount,
					isPayment: data["isPayment"] as? Bool ?? false
				)
				new.id = id
				new.updatedAt = remoteUpdatedAt
				context.insert(new)
			}
		}
	}
}
