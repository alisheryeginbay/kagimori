import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Data") {
                    NavigationLink {
                        TransferView()
                    } label: {
                        Label("Transfer Accounts", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
