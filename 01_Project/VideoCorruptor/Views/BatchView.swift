import SwiftUI
import UniformTypeIdentifiers

struct BatchView: View {
    @Environment(CorruptorViewModel.self) private var viewModel

    var body: some View {
        let batch = viewModel.batchViewModel

        VStack(spacing: 0) {
            batchHeader(batch: batch)

            Divider()

            if batch.jobs.isEmpty {
                batchEmptyState(batch: batch)
            } else {
                batchJobsList(batch: batch)
            }

            Divider()

            batchBottomBar(batch: batch)
        }
        .onDrop(of: [.mpeg4Movie, .quickTimeMovie, .movie, .fileURL], isTargeted: nil) { providers in
            handleBatchDrop(providers: providers, batch: batch)
        }
    }

    // MARK: - Header

    private func batchHeader(batch: BatchViewModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Text("Batch Processing")
                    .font(.headline)
                Text("\(batch.jobs.count) file\(batch.jobs.count == 1 ? "" : "s") in queue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if batch.isProcessing {
                VStack(alignment: .trailing) {
                    ProgressView(value: batch.overallProgress)
                        .frame(width: 100)
                    Text("\(batch.completedCount)/\(batch.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.hasSelections {
                Text("\(viewModel.selectedTypes.count) types")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.tertiary, in: Capsule())
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private func batchEmptyState(batch: BatchViewModel) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("Drop Video Files Here")
                .font(.title3)
                .fontWeight(.medium)

            Text("Or use the button below to add files")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Add Files...") {
                batch.openFilePicker()
            }
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Jobs List

    private func batchJobsList(batch: BatchViewModel) -> some View {
        List {
            ForEach(batch.jobs) { job in
                BatchJobRow(job: job) {
                    batch.removeJob(id: job.id)
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private func batchBottomBar(batch: BatchViewModel) -> some View {
        HStack {
            if !batch.jobs.isEmpty && !batch.isProcessing {
                Button("Add Files...") {
                    batch.openFilePicker()
                }
                .controlSize(.small)

                Button("Clear Queue") {
                    batch.clearQueue()
                }
                .controlSize(.small)
            }

            Spacer()

            // Error mode picker
            Picker("On Error:", selection: Binding(
                get: { batch.errorMode },
                set: { batch.errorMode = $0 }
            )) {
                ForEach(BatchViewModel.ErrorMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .frame(width: 200)
            .controlSize(.small)

            if batch.isProcessing {
                Button("Cancel") {
                    batch.cancelBatch()
                }
                .controlSize(.large)
            } else {
                Button("Start Batch") {
                    batch.startBatch(
                        types: viewModel.selectedTypes,
                        masterSeed: viewModel.currentSeed,
                        severities: viewModel.severities,
                        mode: viewModel.corruptionMode
                    )
                }
                .controlSize(.large)
                .keyboardShortcut(.return)
                .disabled(batch.jobs.isEmpty || !viewModel.hasSelections)
            }
        }
        .padding()
    }

    // MARK: - Drop Handling

    private func handleBatchDrop(providers: [NSItemProvider], batch: BatchViewModel) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        batch.addFiles(urls: [url])
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - Batch Job Row

struct BatchJobRow: View {
    let job: BatchJob
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusIcon

            VStack(alignment: .leading) {
                Text(job.sourceFile.fileName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(job.sourceFile.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(job.statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer()

            if case .processing = job.status {
                ProgressView()
                    .controlSize(.small)
            }

            if !job.results.isEmpty {
                let successes = job.results.filter(\.isSuccess).count
                let failures = job.results.count - successes
                HStack(spacing: 4) {
                    if successes > 0 {
                        Label("\(successes)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    if failures > 0 {
                        Label("\(failures)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }

            if case .pending = job.status {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Group {
            switch job.status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            case .processing:
                Image(systemName: "arrow.circlepath")
                    .foregroundStyle(.blue)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 20)
    }

    private var statusColor: Color {
        switch job.status {
        case .pending: .secondary
        case .processing: .blue
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }
}
