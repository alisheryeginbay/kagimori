import SwiftData
import SwiftUI

@main
struct KagimoriApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([OTPAccount.self])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to configure SwiftData: \(error)")
        }

        let context = ModelContext(modelContainer)
        if let accounts = try? context.fetch(FetchDescriptor<OTPAccount>()) {
            for account in accounts {
                KeychainService.migrateToSyncable(for: account.keychainKey)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
