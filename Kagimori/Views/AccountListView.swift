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
    @State private var copiedAccountID: UUID?

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
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddAccountView()
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

        withAnimation(.easeInOut(duration: 0.15)) {
            copiedAccountID = account.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.15)) {
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
}
