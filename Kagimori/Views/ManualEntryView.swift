import SwiftData
import SwiftUI

struct ManualEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var accountName = ""
    @State private var secret = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var showAdvanced = false

    private var isValid: Bool {
        !issuer.isEmpty
            && !secret.isEmpty
            && Base32.decode(secret.filter { !$0.isWhitespace }) != nil
    }

    var body: some View {
        Form {
            Section("Account") {
                TextField("Issuer (e.g. Google)", text: $issuer)
                    .textContentType(.organizationName)
                TextField("Account (e.g. user@email.com)", text: $accountName)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }

            Section("Secret Key") {
                TextField("Base32 encoded secret", text: $secret)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .fontDesign(.monospaced)
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    Picker("Algorithm", selection: $algorithm) {
                        ForEach(OTPAlgorithm.allCases, id: \.self) { algo in
                            Text(algo.rawValue).tag(algo)
                        }
                    }

                    Picker("Digits", selection: $digits) {
                        Text("6").tag(6)
                        Text("8").tag(8)
                    }

                    Picker("Period", selection: $period) {
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                    }
                }
            }

            Section {
                Button("Add Account") { addAccount() }
                    .disabled(!isValid)
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
        }
    }

    private func addAccount() {
        let cleanSecret = secret
            .filter { !$0.isWhitespace }
            .uppercased()

        let account = OTPAccount(
            issuer: issuer,
            accountName: accountName,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
        KeychainService.save(secret: cleanSecret, for: account.keychainKey)
        modelContext.insert(account)
        dismiss()
    }
}
