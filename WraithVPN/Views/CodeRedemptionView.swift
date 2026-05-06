// CodeRedemptionView.swift
// WraithVPN
//
// Hidden tap-to-redeem flow: Apple Offer Code redemption + account restore via sign-in.
// Compliant with Apple Guideline 3.1.1 (reviewer test access).

import SwiftUI
import StoreKit
import KatafractStyle

struct CodeRedemptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showRedemption = false
    @State private var showSignIn = false
    @State private var redemptionStatus: String? = nil
    @State private var showStatusAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.kataGold)
                    .padding(.top, 40)

                Text("Have a code?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text("Founders, family, and App Review can redeem an Apple Offer Code or sign in to restore an existing subscription.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Button(action: { showRedemption = true }) {
                        Text("Redeem Offer Code")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.kataGold)
                            .foregroundStyle(.black)
                            .font(.system(size: 16, weight: .semibold))
                            .cornerRadius(8)
                    }

                    Button(action: { showSignIn = true }) {
                        Text("Sign in to restore")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.kfSurface.opacity(0.7))
                            .foregroundStyle(.white)
                            .font(.system(size: 16, weight: .semibold))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                Text("Apple Guideline 3.1.1 compliant.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
            }
            .padding()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kataGold)
                }
            }
            .preferredColorScheme(.dark)
            .offerCodeRedemption(isPresented: $showRedemption) { result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        redemptionStatus = "Offer code redeemed successfully!"
                        showStatusAlert = true
                        KataHaptic.unlocked.fire()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    case .failure(let err):
                        redemptionStatus = "Redemption failed: \(err.localizedDescription)"
                        showStatusAlert = true
                        print("[CodeRedemption] error: \(err)")
                    }
                }
            }
            .sheet(isPresented: $showSignIn) {
                SignInRestoreView()
                    .presentationDetents([.medium, .large])
            }
            .alert("Redemption Status", isPresented: $showStatusAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(redemptionStatus ?? "Unknown status")
            }
        }
    }
}

// MARK: - Sign In Restore View

struct SignInRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var recoveryCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var emailSent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Sign In to Restore")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                if emailSent {
                    recoveryCodeView
                } else {
                    emailInputView
                }

                Spacer()

                Text("Check your email within 10 minutes for the recovery code.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.kataGold)
                }
            }
            .preferredColorScheme(.dark)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    private var emailInputView: some View {
        VStack(spacing: 16) {
            Text("Enter your Katafract email address to receive a recovery code.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(Color.kfSurface)
                .cornerRadius(8)
                .padding()

            Button(action: sendRecoveryEmail) {
                if isLoading {
                    ProgressView()
                        .tint(Color.kataGold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Text("Send Recovery Code")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.kataGold)
                        .foregroundStyle(.black)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .disabled(isLoading || email.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding()
        }
    }

    private var recoveryCodeView: some View {
        VStack(spacing: 16) {
            Text("A recovery code has been sent to \(email)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            TextField("Recovery Code", text: $recoveryCode)
                .keyboardType(.default)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(Color.kfSurface)
                .cornerRadius(8)
                .padding()

            Button(action: redeemCode) {
                if isLoading {
                    ProgressView()
                        .tint(Color.kataGold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Text("Restore Subscription")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.kataGold)
                        .foregroundStyle(.black)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .disabled(isLoading || recoveryCode.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding()

            Button("Didn't receive a code? Send another") {
                emailSent = false
                recoveryCode = ""
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color.kataGold)
        }
    }

    private func sendRecoveryEmail() {
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                _ = try await APIClient.shared.recoverByEmail(email.trimmingCharacters(in: .whitespaces))
                emailSent = true
                KataHaptic.tap.fire()
            } catch {
                errorMessage = "Failed to send recovery code: \(error.localizedDescription)"
                showErrorAlert = true
            }
            isLoading = false
        }
    }

    private func redeemCode() {
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let tokenResponse = try await APIClient.shared.redeemRecoveryToken(recoveryCode.trimmingCharacters(in: .whitespaces))

                // Save token to keychain
                try? KeychainHelper.shared.save(tokenResponse.token, for: .subscriptionToken)
                try? KeychainHelper.shared.save(tokenResponse.expiresAt, for: .tokenExpiresAt)
                try? KeychainHelper.shared.save(tokenResponse.plan, for: .tokenPlan)
                if tokenResponse.isFounder {
                    try? KeychainHelper.shared.save("1", for: .tokenIsFounder)
                }

                KataHaptic.unlocked.fire()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            } catch {
                errorMessage = "Recovery failed: \(error.localizedDescription)"
                showErrorAlert = true
            }
            isLoading = false
        }
    }
}

#Preview {
    CodeRedemptionView()
        .preferredColorScheme(.dark)
}
