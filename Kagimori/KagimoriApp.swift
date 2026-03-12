import SwiftData
import SwiftUI

@main
struct KagimoriApp: App {
    var body: some Scene {
        WindowGroup {
            AccountListView()
        }
        .modelContainer(for: OTPAccount.self)
    }
}
