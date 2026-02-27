import SwiftUI

struct SidebarView: View {
    @Environment(CorruptorViewModel.self) private var viewModel

    var body: some View {
        List {
            if viewModel.hasSource {
                corruptionTypesSection
                presetsSection
            } else {
                Section {
                    Label("Drop a video to start", systemImage: "arrow.down.doc")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var corruptionTypesSection: some View {
        ForEach(viewModel.availableCategories) { category in
            Section(category.label) {
                let typesInCategory = viewModel.availableTypes.filter { $0.category == category }
                ForEach(typesInCategory) { type in
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedTypes.contains(type) },
                        set: { _ in viewModel.toggleType(type) }
                    )) {
                        Label(type.label, systemImage: type.icon)
                    }
                    .toggleStyle(.checkbox)
                    .help(type.description)
                }
            }
        }
    }

    private var presetsSection: some View {
        Section("Presets") {
            ForEach(CorruptionPreset.allCases) { preset in
                if preset.isAvailable(for: viewModel.currentFormat) {
                    Button {
                        viewModel.applyPreset(preset)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(preset.label)
                                .font(.body)
                            Text("\(preset.types(for: viewModel.currentFormat).count) types")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(preset.description)
                }
            }
        }
    }
}
