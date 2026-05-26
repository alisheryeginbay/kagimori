import SwiftData
import SwiftUI

struct AddAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var mode: EntryMode = .scan
    @State private var showError = false
    @State private var errorMessage = ""

    enum EntryMode: String, CaseIterable {
        case scan = "Scan QR"
        case manual = "Manual"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Method", selection: $mode) {
                    ForEach(EntryMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .scan:
                    QRScannerView { uri in
                        if let parsed = OTPAuthURI.parse(uri) {
                            saveAccount(parsed)
                        }
                    }
                case .manual:
                    ManualEntryView()
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Add Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveAccount(_ parsed: OTPAuthURI.ParsedAccount) {
        let account = OTPAccount(
            issuer: parsed.issuer,
            accountName: parsed.accountName,
            algorithm: parsed.algorithm,
            digits: parsed.digits,
            period: parsed.period
        )
        guard KeychainService.save(secret: parsed.secret, for: account.keychainKey) else {
            errorMessage = "Couldn't save the secret securely. The account was not added."
            showError = true
            return
        }
        modelContext.insert(account)
        dismiss()
    }
}
