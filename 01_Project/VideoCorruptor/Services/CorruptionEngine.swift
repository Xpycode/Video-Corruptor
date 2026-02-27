import Foundation

/// Orchestrates corruption operations on video files.
/// Always works on copies — never modifies the original.
/// Dispatches to format-specific CorruptionHandler implementations.
@MainActor
final class CorruptionEngine: Sendable {

    private let handlers: [any CorruptionHandler] = [
        FileCorruptor(),
        MP4Corruptor(),
        MXFCorruptor(),
    ]

    /// Apply a set of corruptions to a source file, writing results to outputDir.
    /// Returns one CorruptionResult per corruption type.
    func corrupt(
        source: VideoFile,
        types: [CorruptionType],
        outputDirectory: URL
    ) async -> [CorruptionResult] {
        var results: [CorruptionResult] = []

        for type in types {
            let result = await applySingleCorruption(
                source: source,
                type: type,
                outputDirectory: outputDirectory
            )
            results.append(result)
        }

        return results
    }

    private func applySingleCorruption(
        source: VideoFile,
        type: CorruptionType,
        outputDirectory: URL
    ) async -> CorruptionResult {
        let ext = type == .fakeExtension ? source.fileExtension : outputExtension(for: type, source: source)
        let outputName = "\(source.url.deletingPathExtension().lastPathComponent)_\(type.rawValue).\(ext)"
        let outputURL = outputDirectory.appendingPathComponent(outputName)

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: outputURL.path) {
                try fm.removeItem(at: outputURL)
            }

            switch type {
            case .zeroByteFile:
                fm.createFile(atPath: outputURL.path, contents: Data())

            case .fakeExtension:
                let randomData = Data((0..<1024).map { _ in UInt8.random(in: 0...255) })
                try randomData.write(to: outputURL)

            default:
                try fm.copyItem(at: source.url, to: outputURL)
                try applyMutation(type: type, to: outputURL, source: source)
            }

            // Preserve original file dates
            let sourceAttrs = try fm.attributesOfItem(atPath: source.url.path)
            var dateAttrs: [FileAttributeKey: Any] = [:]
            if let creationDate = sourceAttrs[.creationDate] {
                dateAttrs[.creationDate] = creationDate
            }
            if let modDate = sourceAttrs[.modificationDate] {
                dateAttrs[.modificationDate] = modDate
            }
            if !dateAttrs.isEmpty {
                try? fm.setAttributes(dateAttrs, ofItemAtPath: outputURL.path)
            }

            let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0

            return CorruptionResult(
                sourceFile: source,
                corruptionType: type,
                outputURL: outputURL,
                outputSize: outputSize,
                status: .success,
                detail: type.resultDescription
            )
        } catch {
            return CorruptionResult(
                sourceFile: source,
                corruptionType: type,
                outputURL: outputURL,
                outputSize: 0,
                status: .failed(error.localizedDescription),
                detail: "Failed: \(error.localizedDescription)"
            )
        }
    }

    /// Route to the appropriate handler.
    private func applyMutation(type: CorruptionType, to url: URL, source: VideoFile) throws {
        for handler in handlers {
            if handler.supportedTypes.contains(type) {
                try handler.apply(type, to: url, sourceFile: source)
                return
            }
        }
    }

    /// Determine the output file extension.
    private func outputExtension(for type: CorruptionType, source: VideoFile) -> String {
        source.fileExtension
    }
}

enum CorruptionError: Error, LocalizedError {
    case atomNotFound(String)
    case atomTooSmall(String)

    var errorDescription: String? {
        switch self {
        case .atomNotFound(let type): "Required atom '\(type)' not found in container"
        case .atomTooSmall(let type): "Atom '\(type)' is too small to corrupt meaningfully"
        }
    }
}
