import SwiftUI

@main
struct VideoCorruptorApp: App {
    @State private var viewModel = CorruptorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}
