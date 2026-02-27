import SwiftUI

struct ContentView: View {
    @Environment(CorruptorViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if viewModel.isBatchMode {
                BatchView()
            } else if viewModel.hasSource {
                DetailView()
            } else {
                DropZoneView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Mode toggle: Individual / Stacked
                if viewModel.hasSource && !viewModel.isBatchMode {
                    Picker("Mode", selection: $vm.corruptionMode) {
                        Text("Individual").tag(CorruptionMode.individual)
                        Text("Stacked").tag(CorruptionMode.stacked)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                    .help("Individual: one file per type. Stacked: all types in one file.")
                }

                // Single / Batch toggle
                Toggle(isOn: $vm.isBatchMode) {
                    Label("Batch", systemImage: "square.stack.3d.up")
                }
                .toggleStyle(.button)
                .help("Process multiple files at once")

                if viewModel.hasSource {
                    Button("Clear", systemImage: "xmark.circle") {
                        viewModel.clearAll()
                    }
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
        .environment(CorruptorViewModel())
}
