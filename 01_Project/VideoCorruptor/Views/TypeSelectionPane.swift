import SwiftUI

struct TypeSelectionPane: View {
    @Environment(CorruptorViewModel.self) private var viewModel
    @State private var expandedSeverity: CorruptionType?

    var body: some View {
        List {
            if viewModel.hasSource {
                if viewModel.corruptionMode == .stacked && !viewModel.activeConflicts.isEmpty {
                    conflictsSection
                }
                corruptionTypesSection
                if !viewModel.selectedTypes.isEmpty {
                    severityPresetsSection
                }
                presetsSection
            } else {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("Drop a video to start")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Conflicts

    private var conflictsSection: some View {
        Section("Conflicts") {
            ForEach(viewModel.activeConflicts) { conflict in
                HStack(spacing: 6) {
                    Image(systemName: conflict.severity == .blocker ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(conflict.severity == .blocker ? .red : .orange)
                        .font(.caption)
                    Text(conflict.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Corruption Types

    private var corruptionTypesSection: some View {
        ForEach(viewModel.availableCategories) { category in
            Section(category.label) {
                let typesInCategory = viewModel.availableTypes.filter { $0.category == category }
                ForEach(typesInCategory) { type in
                    CorruptionTypeRow(
                        type: type,
                        isSelected: viewModel.selectedTypes.contains(type),
                        severity: viewModel.severity(for: type),
                        isExpanded: expandedSeverity == type,
                        onToggle: { viewModel.toggleType(type) },
                        onToggleSeverity: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedSeverity = expandedSeverity == type ? nil : type
                            }
                        },
                        onSeverityChange: { viewModel.setSeverity($0, for: type) }
                    )
                }
            }
        }
    }

    // MARK: - Global Severity Presets

    private var severityPresetsSection: some View {
        Section("Global Severity") {
            HStack(spacing: 6) {
                ForEach([
                    ("S", CorruptionSeverity.subtle),
                    ("M", CorruptionSeverity.moderate),
                    ("H", CorruptionSeverity.heavy),
                    ("X", CorruptionSeverity.extreme),
                ], id: \.0) { label, severity in
                    AppKitButton(title: label, action: {
                        viewModel.applyGlobalSeverity(severity)
                    })
                    .appKitControlSize(.small)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - Presets

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

// MARK: - Corruption Type Row

private struct CorruptionTypeRow: View {
    let type: CorruptionType
    let isSelected: Bool
    let severity: CorruptionSeverity
    let isExpanded: Bool
    let onToggle: () -> Void
    let onToggleSeverity: () -> Void
    let onSeverityChange: (CorruptionSeverity) -> Void

    @State private var sliderValue: Double = 0.5

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                    typeLabel
                }
                .toggleStyle(.checkbox)
                .help(type.description)

                if type.hasSeverityControl && isSelected {
                    Button(action: onToggleSeverity) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundColor(isExpanded ? .accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Adjust severity")
                }
            }

            if isExpanded {
                HStack(spacing: 6) {
                    Text("S")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Slider(value: $sliderValue, in: 0.01...1.0)
                        .controlSize(.mini)
                        .onChange(of: sliderValue) { _, newValue in
                            onSeverityChange(CorruptionSeverity(intensity: newValue))
                        }

                    Text("X")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
                .padding(.trailing, 4)
                .onAppear { sliderValue = severity.intensity }
            }
        }
    }

    private var typeLabel: some View {
        Label {
            HStack(spacing: 4) {
                Text(type.label)
                if type.hasSeverityControl && isSelected {
                    Text(type.severityDescription(for: severity))
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: type.icon)
        }
    }
}
