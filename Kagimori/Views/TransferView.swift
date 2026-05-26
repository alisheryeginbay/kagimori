import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TransferView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingFileImporter = false
    @State private var importAlert: ImportAlert?
    @State private var exportItem: ExportItem?

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private struct ExportItem: Identifiable {
        let id = UUID()
        let url: URL
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
            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Saves a 2FAS-format file containing your secrets. The file is unencrypted — store it somewhere safe.")
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
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
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

                let existingAccounts = (try? modelContext.fetch(FetchDescriptor<OTPAccount>())) ?? []
                let snapshot = existingAccounts.map { account in
                    ImportPlanner.ExistingAccount(
                        keychainKey: account.keychainKey,
                        issuer: account.issuer,
                        accountName: account.accountName,
                        secret: KeychainService.retrieve(for: account.keychainKey)
                    )
                }

                var added = 0, restored = 0, skipped = 0, failed = 0
                for entry in parsed {
                    switch ImportPlanner.action(
                        forSecret: entry.secret,
                        issuer: entry.issuer,
                        accountName: entry.accountName,
                        existing: snapshot
                    ) {
                    case .skip:
                        skipped += 1
                    case .restore(let keychainKey):
                        if KeychainService.save(secret: entry.secret, for: keychainKey) {
                            restored += 1
                        } else {
                            failed += 1
                        }
                    case .add:
                        let otp = OTPAccount(
                            issuer: entry.issuer,
                            accountName: entry.accountName,
                            algorithm: entry.algorithm,
                            digits: entry.digits,
                            period: entry.period
                        )
                        if KeychainService.save(secret: entry.secret, for: otp.keychainKey) {
                            modelContext.insert(otp)
                            added += 1
                        } else {
                            failed += 1
                        }
                    }
                }

                var lines = ["Added \(added)", "restored \(restored)", "skipped \(skipped)"]
                if failed > 0 { lines.append("failed \(failed)") }
                importAlert = ImportAlert(title: "Import Complete", message: lines.joined(separator: ", ") + ".")
            } catch {
                importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func exportBackup() {
        let accounts = (try? modelContext.fetch(FetchDescriptor<OTPAccount>())) ?? []
        let exportAccounts = accounts.compactMap { account -> TwoFASExporter.ExportAccount? in
            guard let secret = KeychainService.retrieve(for: account.keychainKey) else { return nil }
            return TwoFASExporter.ExportAccount(
                issuer: account.issuer,
                accountName: account.accountName,
                secret: secret,
                algorithm: account.algorithm,
                digits: account.digits,
                period: account.period
            )
        }
        guard !exportAccounts.isEmpty else {
            importAlert = ImportAlert(title: "Nothing to Export", message: "No accounts with a stored secret were found.")
            return
        }
        do {
            let data = try TwoFASExporter.makeBackup(from: exportAccounts)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("kagimori-backup.2fas")
            try data.write(to: url, options: .atomic)
            exportItem = ExportItem(url: url)
        } catch {
            importAlert = ImportAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }
}
