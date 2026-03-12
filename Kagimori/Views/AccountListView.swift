import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let twoFASBackup = UTType(
        importedAs: "com.twofas.backup",
        conformingTo: .json
    )
}

struct AccountListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \OTPAccount.createdAt) private var accounts: [OTPAccount]
    @State private var showingAddSheet = false
    @State private var showingFileImporter = false
    @State private var importAlert: ImportAlert?
    @State private var copiedAccountID: UUID?

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Group {
                    if accounts.isEmpty {
                        emptyState
                    } else {
                        accountList(date: context.date)
                    }
                }
            }
            .navigationTitle("Kagimori")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Add Account", systemImage: "plus")
                        }
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Import from 2FAS", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddAccountView()
            }
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
    }

    private func accountList(date: Date) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(accounts) { account in
                    CodeCardView(
                        account: account,
                        date: date,
                        isCopied: copiedAccountID == account.id
                    )
                    .onTapGesture {
                        copyCode(for: account, date: date)
                    }
                    .contextMenu {
                        Button {
                            copyCode(for: account, date: date)
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            deleteAccount(account)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Accounts", systemImage: "key.2.on.ring")
        } description: {
            Text("Add your first account to start generating verification codes.")
        } actions: {
            Button("Add Account") {
                showingAddSheet = true
            }
            .buttonStyle(.glass)
        }
    }

    private func copyCode(for account: OTPAccount, date: Date) {
        guard let secret = KeychainService.retrieve(for: account.keychainKey) else { return }
        let code = TOTPGenerator.generate(
            secret: secret,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
            date: date
        )
        UIPasteboard.general.string = code
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation {
            copiedAccountID = account.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedAccountID == account.id {
                    copiedAccountID = nil
                }
            }
        }
    }

    private func deleteAccount(_ account: OTPAccount) {
        KeychainService.delete(for: account.keychainKey)
        modelContext.delete(account)
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
