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
            if #available(macOS 26.0, *) {
                toolbarItems
                    .sharedBackgroundVisibility(.hidden)
            } else {
                toolbarItems
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

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    if viewModel.isBatchMode {
                        viewModel.batchViewModel.openFilePicker()
                    } else {
                        viewModel.openFilePicker()
                    }
                }) {
                    Image(systemName: "plus")
                }
                .help("Open a video file")
                .buttonStyle(AppKitToolbarButtonStyle(isOn: .constant(false)))
            }

            // A real principal item gives NSToolbar the flexible-space anchors
            // it needs to keep primary actions at the trailing edge.
            ToolbarItemGroup(placement: .principal) {
                Spacer()
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 7) {
                    Button(action: { viewModel.isBatchMode.toggle() }) {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .help("Process multiple files at once")
                    .buttonStyle(AppKitToolbarButtonStyle(isOn: Binding(
                        get: { viewModel.isBatchMode },
                        set: { viewModel.isBatchMode = $0 }
                    )))

                    if viewModel.hasSource {
                        Button(action: { viewModel.clearAll() }) {
                            Image(systemName: "xmark.circle")
                        }
                        .help("Clear current file and selections")
                        .buttonStyle(AppKitToolbarButtonStyle(isOn: .constant(false)))
                    }
                }
                // Prevent SwiftUI from adding a second toolbar-button wrapper
                // around the custom fixed-size button boxes.
                .buttonStyle(.borderless)
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
