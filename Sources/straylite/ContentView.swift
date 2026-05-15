import SwiftUI

/// Root navigation. Two destinations:
/// - SessionListView — historic scans, can be opened/shared
/// - CaptureView      — live scanning screen (modal sheet)
struct ContentView: View {
    @State private var presentingCapture = false

    var body: some View {
        NavigationStack {
            SessionListView()
                .navigationTitle("StrayLite")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            presentingCapture = true
                        } label: {
                            Label("New scan", systemImage: "plus.viewfinder")
                        }
                    }
                }
                .sheet(isPresented: $presentingCapture) {
                    CaptureView()
                }
        }
    }
}

