import SwiftUI

struct DetailView: View {
    @Environment(CorruptorViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            sourceFileHeader

            Divider()

            ZStack {
                if viewModel.results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }

                if viewModel.isProcessing {
                    processingOverlay
                }
            }

            Divider()

            bottomBar
        }
    }

    // MARK: - Source File Header

    private var sourceFileHeader: some View {
        @Bindable var vm = viewModel

        return HStack(spacing: 12) {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.secondary)

            if let file = viewModel.sourceFile {
                VStack(alignment: .leading) {
                    Text(file.fileName)
                        .font(.headline)
                    Text(file.formattedSize)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("Mode", selection: $vm.corruptionMode) {
                Text("Individual").tag(CorruptionMode.individual)
                Text("Stacked").tag(CorruptionMode.stacked)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .help("Individual: one file per type. Stacked: all types in one file.")

            if viewModel.hasSelections {
                Text("\(viewModel.selectedTypes.count) selected")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.tertiary, in: Capsule())
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Select corruption types to begin")
                .foregroundStyle(.secondary)
            Text("Then click \"Corrupt\" to generate test files")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Corrupting…")
                .font(.title3)
                .fontWeight(.medium)

            Text("\(viewModel.selectedTypes.count) type\(viewModel.selectedTypes.count == 1 ? "" : "s") being applied")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List(viewModel.results) { result in
            ResultRow(result: result)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: 8) {
            // Seed controls row
            HStack(spacing: 6) {
                Image(systemName: "die.face.5")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("Seed", text: $vm.seedText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .font(.system(.caption, design: .monospaced))
                    .onSubmit { viewModel.applySeedFromText() }

                Button {
                    viewModel.generateNewSeed()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Generate new random seed")

                Button {
                    viewModel.copySeedToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy seed to clipboard")

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Actions row
            HStack {
                if !viewModel.results.isEmpty {
                    HStack(spacing: 12) {
                        Label("\(viewModel.successCount) created", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if viewModel.failureCount > 0 {
                            Label("\(viewModel.failureCount) failed", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption)

                    if let dir = viewModel.outputDirectory {
                        AppKitButton(title: "Reveal in Finder", action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                        })
                        .appKitControlSize(.small)
                        .fixedSize()
                    }
                }

                Spacer()

                if viewModel.isProcessing {
                    // Processing indicator now shown as overlay in content area
                    Text("Processing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    AppKitButton(title: "Corrupt", action: {
                        viewModel.selectOutputAndCorrupt()
                    })
                    .appKitDefault()
                    .appKitEnabled(viewModel.canCorrupt)
                    .fixedSize()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Result Row

struct ResultRow: View {
    let result: CorruptionResult

    var body: some View {
        HStack {
            Image(systemName: result.corruptionType.icon)
                .frame(width: 20)
                .foregroundColor(result.isSuccess ? .primary : .red)

            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(result.corruptionType.label)
                        .font(.body)
                    if let severity = result.severity, result.corruptionType.hasSeverityControl {
                        Text(result.corruptionType.severityDescription(for: severity))
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
                Text(result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if result.isSuccess {
                Text(ByteCountFormatter.string(fromByteCount: result.outputSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}
