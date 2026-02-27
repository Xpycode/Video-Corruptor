import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(CorruptorViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        HSplitView {
            // MARK: - Left Pane (Type Selection)

            VStack(spacing: 0) {
                TypeSelectionPane()
                    .frame(maxHeight: .infinity)

                Divider()

                footerBar
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 400)

            // MARK: - Right Pane (Content)

            Group {
                if viewModel.isBatchMode {
                    BatchView()
                } else if viewModel.hasSource {
                    DetailView()
                } else {
                    DropZoneView()
                }
            }
            .frame(minWidth: 400)
        }
        .autosaveSplitView(named: "MainSplitView")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    if viewModel.isBatchMode {
                        viewModel.batchViewModel.openFilePicker()
                    } else {
                        viewModel.openFilePicker()
                    }
                }) {
                    Image(systemName: "plus")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
                .help("Open a video file")
                .buttonStyle(AppKitToolbarButtonStyle(isOn: .constant(false)))
            }

            ToolbarItemGroup(placement: .primaryAction) {
                HStack {
                    Button(action: { vm.isBatchMode.toggle() }) {
                        Image(systemName: "square.stack.3d.up")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    }
                    .help("Process multiple files at once")
                    .buttonStyle(AppKitToolbarButtonStyle(isOn: $vm.isBatchMode))

                    if viewModel.hasSource {
                        Button(action: { viewModel.clearAll() }) {
                            Image(systemName: "xmark.circle")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        .help("Clear current file and selections")
                        .buttonStyle(AppKitToolbarButtonStyle(isOn: .constant(false)))
                    }
                }
            }
        }
        .toolbarRole(.editor)
        .onDrop(of: [.mpeg4Movie, .quickTimeMovie, .movie, .fileURL], isTargeted: nil) { providers in
            if viewModel.isBatchMode {
                return handleBatchDrop(providers: providers)
            } else {
                return viewModel.handleDrop(providers: providers)
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

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            if viewModel.hasSource {
                Text("\(viewModel.selectedTypes.count) of \(viewModel.availableTypes.count) types")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !viewModel.selectedTypes.isEmpty {
                    AppKitButton(title: "Deselect", action: {
                        viewModel.selectedTypes.removeAll()
                    })
                    .appKitControlSize(.mini)
                    .fixedSize()
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Batch Drop

    private func handleBatchDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        viewModel.batchViewModel.addFiles(urls: [url])
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

#Preview {
    ContentView()
        .environment(CorruptorViewModel())
}
