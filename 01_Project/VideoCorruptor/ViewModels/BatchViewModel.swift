import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class BatchViewModel {

    // MARK: - State

    var jobs: [BatchJob] = []
    var isProcessing = false
    var overallProgress: Double = 0
    var errorMode: ErrorMode = .skipAndContinue
    var outputDirectory: URL?

    private var batchTask: Task<Void, Never>?
    private let engine = CorruptionEngine()

    enum ErrorMode: String, CaseIterable, Sendable {
        case skipAndContinue = "Skip & Continue"
        case stopOnError = "Stop on Error"
    }

    // MARK: - Computed

    var hasJobs: Bool { !jobs.isEmpty }
    var completedCount: Int { jobs.filter(\.isComplete).count }
    var totalCount: Int { jobs.count }

    // MARK: - Queue Management

    func addFiles(urls: [URL]) {
        for url in urls {
            let file = VideoFile(url: url)
            guard file.isSupported else { continue }
            // Avoid duplicates
            guard !jobs.contains(where: { $0.sourceFile.url == url }) else { continue }
            jobs.append(BatchJob(sourceFile: file))
        }
    }

    func removeJob(id: UUID) {
        jobs.removeAll { $0.id == id }
    }

    func clearQueue() {
        guard !isProcessing else { return }
        jobs = []
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select video files for batch processing"

        if let mxfType = UTType(filenameExtension: "mxf") {
            panel.allowedContentTypes.append(mxfType)
        }

        if panel.runModal() == .OK {
            addFiles(urls: panel.urls)
        }
    }

    // MARK: - Batch Execution

    func startBatch(
        types: Set<CorruptionType>,
        masterSeed: UInt64,
        severities: [CorruptionType: CorruptionSeverity],
        mode: CorruptionMode
    ) {
        guard !isProcessing else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output directory for batch processing"
        panel.prompt = "Save Here"

        guard panel.runModal() == .OK, let dir = panel.url else { return }
        outputDirectory = dir

        isProcessing = true
        overallProgress = 0

        // Reset job statuses
        for i in jobs.indices {
            jobs[i].status = .pending
            jobs[i].progress = 0
            jobs[i].results = []
        }

        let sortedTypes = Array(types).sorted { $0.rawValue < $1.rawValue }

        batchTask = Task {
            // Bounded concurrency: process 2 jobs at a time
            let concurrency = 2
            var index = 0

            while index < jobs.count {
                let batchEnd = min(index + concurrency, jobs.count)
                let chunk = index..<batchEnd

                await withTaskGroup(of: (Int, [CorruptionResult], BatchJob.BatchJobStatus).self) { group in
                    for jobIndex in chunk {
                        guard !Task.isCancelled else { break }

                        let job = jobs[jobIndex]
                        jobs[jobIndex].status = .processing

                        group.addTask { [engine] in
                            // Create per-source subfolder
                            let sourceName = job.sourceFile.url.deletingPathExtension().lastPathComponent
                            let subfolder = dir.appendingPathComponent(sourceName)
                            try? FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

                            do {
                                let results: [CorruptionResult]
                                switch mode {
                                case .individual:
                                    results = await engine.corrupt(
                                        source: job.sourceFile,
                                        types: sortedTypes,
                                        outputDirectory: subfolder,
                                        masterSeed: masterSeed,
                                        severities: severities,
                                        mode: .individual
                                    )
                                case .stacked:
                                    let result = await engine.corruptStacked(
                                        source: job.sourceFile,
                                        types: sortedTypes,
                                        outputDirectory: subfolder,
                                        masterSeed: masterSeed,
                                        severities: severities
                                    )
                                    results = [result]
                                }
                                let hasFailure = results.contains { !$0.isSuccess }
                                let status: BatchJob.BatchJobStatus = hasFailure ? .failed("Some corruptions failed") : .completed
                                return (jobIndex, results, status)
                            }
                        }
                    }

                    for await (jobIndex, results, status) in group {
                        jobs[jobIndex].results = results
                        jobs[jobIndex].status = status
                        jobs[jobIndex].progress = 1.0
                        overallProgress = Double(completedCount) / Double(totalCount)

                        // Stop on error if configured
                        if case .failed = status, errorMode == .stopOnError {
                            batchTask?.cancel()
                        }
                    }
                }

                if Task.isCancelled {
                    // Mark remaining as cancelled
                    for i in batchEnd..<jobs.count {
                        if case .pending = jobs[i].status {
                            jobs[i].status = .cancelled
                        }
                    }
                    break
                }

                index = batchEnd
            }

            // Write manifest
            writeBatchManifest(to: dir, masterSeed: masterSeed)

            overallProgress = 1.0
            isProcessing = false
        }
    }

    func cancelBatch() {
        batchTask?.cancel()
        for i in jobs.indices {
            if case .processing = jobs[i].status {
                jobs[i].status = .cancelled
            }
            if case .pending = jobs[i].status {
                jobs[i].status = .cancelled
            }
        }
        isProcessing = false
    }

    // MARK: - Manifest

    private func writeBatchManifest(to dir: URL, masterSeed: UInt64) {
        let entries = jobs.flatMap { job -> [BatchManifest.ManifestEntry] in
            job.results.map { result in
                BatchManifest.ManifestEntry(
                    sourceFile: job.sourceFile.fileName,
                    corruptionType: result.corruptionType.rawValue,
                    outputFile: result.outputURL.lastPathComponent,
                    status: result.isSuccess ? "success" : "failed",
                    severity: result.severity?.intensity,
                    seed: result.seed.map { SeedFormatting.format($0) },
                    stackedTypes: result.stackedTypes?.map(\.rawValue)
                )
            }
        }

        let manifest = BatchManifest(
            generatedAt: Date(),
            masterSeed: SeedFormatting.format(masterSeed),
            entries: entries
        )

        let manifestURL = dir.appendingPathComponent("batch_manifest.json")
        try? manifest.write(to: manifestURL)
    }
}
