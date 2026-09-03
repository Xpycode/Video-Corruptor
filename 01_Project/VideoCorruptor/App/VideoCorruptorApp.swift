import SwiftUI

@main
struct VideoCorruptorApp: App {
    @State private var viewModel = CorruptorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
        // Match the compact unified toolbar shell used by Conjoyn and
        // Penumbra instead of reserving a separate standard title strip.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}
