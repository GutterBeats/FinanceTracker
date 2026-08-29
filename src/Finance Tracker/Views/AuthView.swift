//
//  AuthView.swift
//  Finance Tracker
//
//  Created by Anthony Lesch on 8/24/26.
//

import SwiftUI
import FirebaseAuth

struct AuthView: View {
    var onSignedIn: () -> Void

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSigningUp: Bool = false
    @State private var errorMessage: String?
    @State private var isWorking: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Finance Tracker")
                .font(.largeTitle.bold())

            Text("Sign in with the same account on every device to keep them in sync.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(isSigningUp ? "Create Account" : "Sign In") {
                submit()
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.count < 6 || isWorking)

            Button(isSigningUp ? "Already have an account? Sign In" : "New here? Create an Account") {
                isSigningUp.toggle()
                errorMessage = nil
            }
            .font(.footnote)
        }
        .padding(32)
        .frame(maxWidth: 400)
    }

    private func submit() {
        isWorking = true
        errorMessage = nil

        let completion: (AuthDataResult?, Error?) -> Void = { _, error in
            isWorking = false
            if let error {
                errorMessage = error.localizedDescription
                return
            }
            onSignedIn()
        }

        if isSigningUp {
            Auth.auth().createUser(withEmail: email, password: password, completion: completion)
        } else {
            Auth.auth().signIn(withEmail: email, password: password, completion: completion)
        }
    }
}

#Preview {
    AuthView(onSignedIn: {})
}
