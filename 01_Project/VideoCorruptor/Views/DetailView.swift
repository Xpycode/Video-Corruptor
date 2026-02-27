import SwiftUI

struct DetailView: View {
    @Environment(CorruptorViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            sourceFileHeader

            Divider()

            if viewModel.results.isEmpty {
                emptyState
            } else {
                resultsList
            }

            Divider()

            bottomBar
        }
    }

    // MARK: - Source File Header

    private var sourceFileHeader: some View {
        HStack(spacing: 12) {
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
            Text("Select corruption types in the sidebar")
                .foregroundStyle(.secondary)
            Text("Then click \"Corrupt\" to generate test files")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List(viewModel.results) { result in
            ResultRow(result: result)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
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
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                    }
                    .controlSize(.small)
                }
            }

            Spacer()

            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
                Text("Corrupting...")
                    .foregroundStyle(.secondary)
            } else {
                Button("Corrupt") {
                    viewModel.selectOutputAndCorrupt()
                }
                .controlSize(.large)
                .keyboardShortcut(.return)
                .disabled(!viewModel.canCorrupt)
            }
        }
        .padding()
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
                Text(result.corruptionType.label)
                    .font(.body)
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
