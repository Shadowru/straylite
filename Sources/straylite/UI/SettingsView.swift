import SwiftUI

/// Settings screen — server URL + bearer token + VLM preferences.
/// All values live in UserDefaults via @AppStorage. The token is plain
/// text in defaults (good enough for a personal install; switch to
/// Keychain if you ever distribute the app).
struct SettingsView: View {
    @AppStorage(SettingsKey.serverURL)   private var serverURL: String = ""
    @AppStorage(SettingsKey.uploadToken) private var uploadToken: String = ""
    @AppStorage(SettingsKey.useVLM)      private var useVLM: Bool = true
    @AppStorage(SettingsKey.vlmFrames)   private var vlmFrames: Int = 3

    @State private var probing = false
    @State private var probeResult: String?
    @State private var probeOK = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("https://light.extra.moscow", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Bearer token", text: $uploadToken)
                        .autocorrectionDisabled()
                    Button {
                        probe()
                    } label: {
                        HStack {
                            if probing {
                                ProgressView().controlSize(.small)
                            }
                            Text(probing ? "Checking…" : "Check connection")
                        }
                    }
                    .disabled(probing || serverURL.isEmpty)
                    if let r = probeResult {
                        Text(r)
                            .font(.caption)
                            .foregroundStyle(probeOK ? .green : .red)
                    }
                }

                Section("Processing") {
                    Toggle("Run local VLM on server", isOn: $useVLM)
                    if useVLM {
                        Stepper("Frames sent to VLM: \(vlmFrames)",
                                value: $vlmFrames, in: 1...8)
                        Text("More frames = better detection of plants / lamps / colours, slower processing on the server.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "StrayLite v0.3")
                    Text("Captures RGB + depth + camera poses + RoomPlan, "
                       + "ships them to the backend for conversion into a "
                       + ".set file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func probe() {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)) else {
            probeResult = "Bad URL"
            probeOK = false
            return
        }
        probing = true
        probeResult = nil
        let endpoint = url.appendingPathComponent("api/health")
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                probing = false
                if let err {
                    probeResult = "Network error: \(err.localizedDescription)"
                    probeOK = false
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    probeResult = "No HTTP response"
                    probeOK = false
                    return
                }
                if http.statusCode == 200, let data,
                   let s = String(data: data, encoding: .utf8) {
                    probeResult = "OK — server says: \(s)"
                    probeOK = true
                } else {
                    probeResult = "HTTP \(http.statusCode)"
                    probeOK = false
                }
            }
        }.resume()
    }
}
