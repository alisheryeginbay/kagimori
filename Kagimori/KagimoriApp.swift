import SwiftData
import SwiftUI

@main
struct KagimoriApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: OTPAccount.self)
    }
}
