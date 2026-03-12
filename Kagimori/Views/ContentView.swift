import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Codes", systemImage: "key.2.on.ring") {
                AccountListView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
