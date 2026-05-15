import SwiftUI

@main
struct StrayLiteApp: App {
    @StateObject private var store = SessionsStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
