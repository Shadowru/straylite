import SwiftUI

/// Root navigation. Two destinations:
/// - SessionListView — historic scans, can be opened/shared
/// - CaptureView      — live scanning screen (modal sheet)
struct ContentView: View {
    @State private var presentingCapture = false
    @State private var presentingSettings = false

    var body: some View {
        NavigationStack {
            SessionListView()
                .navigationTitle("StrayLite")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            presentingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            presentingCapture = true
                        } label: {
                            Label("New scan", systemImage: "plus.viewfinder")
                        }
                    }
                }
                .fullScreenCover(isPresented: $presentingCapture) {
                    CaptureView()
                }
                .sheet(isPresented: $presentingSettings) {
                    SettingsView()
                }
        }
    }
}

