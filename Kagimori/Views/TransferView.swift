import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TransferView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingFileImporter = false
    @State private var importAlert: ImportAlert?

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingFileImporter = true
                } label: {
                    Label {
                        Text("2FAS Authenticator")
                    } icon: {
                        Image("2fas")
                            .resizable()
                            .scaledToFit()
                    }
                }
            } header: {
                Text("Import from")
            } footer: {
                Text("Select a backup file exported from your previous authenticator app.")
            }
        }
        .navigationTitle("Transfer Accounts")
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.twoFASBackup, .json, .data]
        ) { result in
            importFile(result)
        }
        .alert(item: $importAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func importFile(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importAlert = ImportAlert(title: "Import Failed", message: "Unable to access the selected file.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let parsed = try TwoFASImporter.parse(data: data)
                guard !parsed.isEmpty else {
                    importAlert = ImportAlert(title: "No Accounts Found", message: "The file contained no TOTP accounts to import.")
                    return
                }
                for account in parsed {
                    let otp = OTPAccount(
                        issuer: account.issuer,
                        accountName: account.accountName,
                        algorithm: account.algorithm,
                        digits: account.digits,
                        period: account.period
                    )
                    KeychainService.save(secret: account.secret, for: otp.keychainKey)
                    modelContext.insert(otp)
                }
                importAlert = ImportAlert(
                    title: "Import Successful",
                    message: "Imported \(parsed.count) account\(parsed.count == 1 ? "" : "s")."
                )
            } catch {
                importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }
}
