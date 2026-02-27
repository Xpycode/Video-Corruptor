import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Purpose", value: "Generate corrupted video files for testing")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .navigationTitle("Settings")
    }
}
