import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class CorruptorViewModel {

    // MARK: - State

    var sourceFile: VideoFile?
    var selectedTypes: Set<CorruptionType> = []
    var results: [CorruptionResult] = []
    var isProcessing = false
    var outputDirectory: URL?
    var errorMessage: String?

    // MARK: - Computed

    var hasSource: Bool { sourceFile != nil }
    var hasSelections: Bool { !selectedTypes.isEmpty }
    var canCorrupt: Bool { hasSource && hasSelections && !isProcessing }

    var successCount: Int { results.filter(\.isSuccess).count }
    var failureCount: Int { results.filter { !$0.isSuccess }.count }

    /// The detected format of the loaded file, if any.
    var currentFormat: VideoFormat? { sourceFile?.detectedFormat }

    /// Corruption types available for the current file's format.
    var availableTypes: [CorruptionType] {
        guard let format = currentFormat else {
            return CorruptionType.allCases
        }
        return CorruptionType.allCases.filter { $0.supportedFormats.contains(format) }
    }

    /// Categories that have at least one available type for the current format.
    var availableCategories: [CorruptionCategory] {
        let available = Set(availableTypes.map(\.category))
        return CorruptionCategory.allCases.filter { available.contains($0) }
    }

    // MARK: - Engine

    private let engine = CorruptionEngine()

    // MARK: - Actions

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        let types: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie]

        for type in types {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadItem(forTypeIdentifier: type.identifier) { [weak self] item, _ in
                    guard let url = item as? URL else { return }
                    Task { @MainActor in
                        self?.setSource(url: url)
                    }
                }
                return true
            }
        }

        // Fallback: try file URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    self?.setSource(url: url)
                }
            }
            return true
        }

        return false
    }

    func setSource(url: URL) {
        let file = VideoFile(url: url)
        guard file.isSupported else {
            errorMessage = "Unsupported format: .\(file.fileExtension). Use MP4, MOV, M4V, or MXF."
            return
        }
        sourceFile = file
        results = []
        errorMessage = nil

        // Clear any selections that don't apply to the new format
        if let format = file.detectedFormat {
            selectedTypes = selectedTypes.filter { $0.supportedFormats.contains(format) }
        }
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a video file to corrupt"

        // Also allow MXF by extension since there's no standard UTType for it
        if let mxfType = UTType(filenameExtension: "mxf") {
            panel.allowedContentTypes.append(mxfType)
        }

        if panel.runModal() == .OK, let url = panel.url {
            setSource(url: url)
        }
    }

    func applyPreset(_ preset: CorruptionPreset) {
        selectedTypes = Set(preset.types(for: currentFormat))
    }

    func toggleType(_ type: CorruptionType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
    }

    func selectOutputAndCorrupt() {
        guard let source = sourceFile else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where to save corrupted files"
        panel.prompt = "Save Here"

        if panel.runModal() == .OK, let dir = panel.url {
            outputDirectory = dir
            Task {
                await runCorruption(source: source, outputDir: dir)
            }
        }
    }

    func clearResults() {
        results = []
    }

    func clearAll() {
        sourceFile = nil
        selectedTypes = []
        results = []
        errorMessage = nil
    }

    // MARK: - Private

    private func runCorruption(source: VideoFile, outputDir: URL) async {
        isProcessing = true
        results = []

        let types = Array(selectedTypes).sorted { $0.rawValue < $1.rawValue }
        results = await engine.corrupt(
            source: source,
            types: types,
            outputDirectory: outputDir
        )

        isProcessing = false
    }
}
