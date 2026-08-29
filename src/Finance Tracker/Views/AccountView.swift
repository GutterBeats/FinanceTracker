//
//  AccountView.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/28/26.
//

import SwiftUI
import FirebaseAuth

struct AccountView: View {
	@Environment(\.dismiss) private var dismiss
	@State private var errorMessage: String?

	private var userEmail: String {
		Auth.auth().currentUser?.email ?? "Unknown"
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					LabeledContent("Email", value: userEmail)
				}

				Section {
					Button("Sign Out", role: .destructive) {
						signOut()
					}
				}

				if let errorMessage {
					Section {
						Text(errorMessage)
							.font(.footnote)
							.foregroundStyle(.red)
					}
				}
			}
			.navigationTitle("Account")
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
	}

	private func signOut() {
		do {
			try Auth.auth().signOut()
			dismiss()
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}

#Preview {
	AccountView()
}
