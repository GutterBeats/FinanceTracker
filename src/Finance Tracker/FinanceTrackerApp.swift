//
//  Finance_TrackerApp.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/23/26.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth

@main
struct FinanceTrackerApp: App {
	var sharedModelContainer: ModelContainer = {
		let schema = Schema([
			Transaction.self,
			Category.self,
			PaymentAccount.self,
		])

		let modelConfiguration = ModelConfiguration(
			schema: schema,
			isStoredInMemoryOnly: false
		)

		do {
			return try ModelContainer(for: schema, configurations: [modelConfiguration])
		} catch {
			fatalError("Could not create ModelContainer: \(error)")
		}
	}()

	init() {
		FirebaseApp.configure()
	}

	var body: some Scene {
		WindowGroup {
			RootView()
		}
		.modelContainer(sharedModelContainer)
	}
}

/// Gates the app behind sign-in, then starts/stops Firestore sync listeners
/// around the signed-in session.
private struct RootView: View {
	@Environment(\.modelContext) private var modelContext
	@State private var isSignedIn = Auth.auth().currentUser != nil
	@StateObject private var syncService = SyncService.shared

	var body: some View {
		Group {
			if isSignedIn {
				BudgetOverviewView()
			} else {
				AuthView {
					isSignedIn = true
				}
			}
		}
		.onChange(of: isSignedIn) { _, signedIn in
			if signedIn {
				// Upload anything created locally before sign-in (e.g. if you
				// used the app for a bit before setting up sync), then start
				// listening for changes from other devices.
				syncService.pushAllLocalData(context: modelContext)
				syncService.startListening(context: modelContext)
			} else {
				syncService.stopListening()
			}
		}
		.onAppear {
			if isSignedIn {
				syncService.startListening(context: modelContext)
			}
		}
	}
}
