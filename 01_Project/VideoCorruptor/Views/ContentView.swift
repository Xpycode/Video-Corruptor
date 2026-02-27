import SwiftUI

struct ContentView: View {
    @Environment(CorruptorViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if viewModel.hasSource {
                DetailView()
            } else {
                DropZoneView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
