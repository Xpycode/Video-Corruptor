import Foundation

/// Orchestrates corruption operations on video files.
/// Always works on copies — never modifies the original.
/// Dispatches to format-specific CorruptionHandler implementations.
final class CorruptionEngine: Sendable {

    private let handlers: [any CorruptionHandler] = [
        FileCorruptor(),
        MP4Corruptor(),
        MXFCorruptor(),
    ]

    /// Apply a set of corruptions to a source file, writing results to outputDir.
    /// Each type gets an independent sub-RNG derived from the master seed.
    /// Returns one CorruptionResult per corruption type.
    func corrupt(
        source: VideoFile,
        types: [CorruptionType],
        outputDirectory: URL,
        masterSeed: UInt64,
        severities: [CorruptionType: CorruptionSeverity] = [:],
        mode: CorruptionMode = .individual
    ) async -> [CorruptionResult] {
        var results: [CorruptionResult] = []

        for type in types {
            let rng = SeedDerivation.rng(master: masterSeed, for: type)
            let severity = severities[type] ?? .moderate
            var context = CorruptionContext(rng: rng, severity: severity, mode: mode)

            let result = await applySingleCorruption(
                source: source,
                type: type,
                outputDirectory: outputDirectory,
                context: &context,
                seed: masterSeed
            )
            results.append(result)
        }

        return results
    }

    /// Apply multiple corruptions to a single output file (stacked mode).
    /// Types are sorted by phase (inner -> outer) and applied sequentially.
    func corruptStacked(
        source: VideoFile,
        types: [CorruptionType],
        outputDirectory: URL,
        masterSeed: UInt64,
        severities: [CorruptionType: CorruptionSeverity] = [:]
    ) async -> CorruptionResult {
        let sorted = types.sorted { $0.phase.rawValue < $1.phase.rawValue }
        let baseName = source.url.deletingPathExtension().lastPathComponent
        let ext = source.fileExtension
        let typeSuffix = sorted.map(\.rawValue).joined(separator: "+")
        let outputName = "\(baseName)_stacked_\(typeSuffix).\(ext)"
        let outputURL = outputDirectory.appendingPathComponent(outputName)

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: outputURL.path) {
                try fm.removeItem(at: outputURL)
            }

            // Check for exclusive types that can't stack
            let hasExclusive = sorted.contains { $0 == .zeroByteFile || $0 == .fakeExtension }
            if hasExclusive {
                // Just apply the first exclusive type
                let exclusive = sorted.first { $0 == .zeroByteFile || $0 == .fakeExtension }!
                var ctx = CorruptionContext(rng: SeedDerivation.rng(master: masterSeed, for: exclusive))
                return await applySingleCorruption(
                    source: source,
                    type: exclusive,
                    outputDirectory: outputDirectory,
                    context: &ctx,
                    seed: masterSeed
                )
            }

            // Copy once
            try fm.copyItem(at: source.url, to: outputURL)

            var appliedTypes: [CorruptionType] = []
            for type in sorted {
                let rng = SeedDerivation.rng(master: masterSeed, for: type)
                let severity = severities[type] ?? .moderate
                var context = CorruptionContext(rng: rng, severity: severity, mode: .stacked)

                try applyMutation(type: type, to: outputURL, source: source, context: &context)
                appliedTypes.append(type)
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
            let detail = "Stacked: \(appliedTypes.map(\.label).joined(separator: " + "))"

            return CorruptionResult(
                sourceFile: source,
                corruptionType: appliedTypes.first ?? sorted[0],
                outputURL: outputURL,
                outputSize: outputSize,
                status: .success,
                detail: detail,
                seed: masterSeed,
                severity: nil,
                stackedTypes: appliedTypes
            )
        } catch {
            return CorruptionResult(
                sourceFile: source,
                corruptionType: sorted.first ?? .truncation,
                outputURL: outputURL,
                outputSize: 0,
                status: .failed(error.localizedDescription),
                detail: "Stacked corruption failed: \(error.localizedDescription)",
                seed: masterSeed,
                severity: nil,
                stackedTypes: sorted
            )
        }
    }

    private func applySingleCorruption(
        source: VideoFile,
        type: CorruptionType,
        outputDirectory: URL,
        context: inout CorruptionContext,
        seed: UInt64
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
                let randomData = Data((0..<1024).map { _ in UInt8.random(in: 0...255, using: &context.rng) })
                try randomData.write(to: outputURL)

            default:
                try fm.copyItem(at: source.url, to: outputURL)
                try applyMutation(type: type, to: outputURL, source: source, context: &context)
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
                detail: type.resultDescription(for: context.severity),
                seed: seed,
                severity: context.severity
            )
        } catch {
            return CorruptionResult(
                sourceFile: source,
                corruptionType: type,
                outputURL: outputURL,
                outputSize: 0,
                status: .failed(error.localizedDescription),
                detail: "Failed: \(error.localizedDescription)",
                seed: seed,
                severity: context.severity
            )
        }
    }

    /// Route to the appropriate handler.
    private func applyMutation(type: CorruptionType, to url: URL, source: VideoFile, context: inout CorruptionContext) throws {
        for handler in handlers {
            if handler.supportedTypes.contains(type) {
                try handler.apply(type, to: url, sourceFile: source, context: &context)
                return
            }
        }
        throw CorruptionError.unsupportedType(type.rawValue)
    }

    /// Determine the output file extension.
    private func outputExtension(for type: CorruptionType, source: VideoFile) -> String {
        source.fileExtension
    }
}

enum CorruptionError: Error, LocalizedError {
    case atomNotFound(String)
    case atomTooSmall(String)
    case unsupportedType(String)

    var errorDescription: String? {
        switch self {
        case .atomNotFound(let type): "Required atom '\(type)' not found in container"
        case .atomTooSmall(let type): "Atom '\(type)' is too small to corrupt meaningfully"
        case .unsupportedType(let type): "No handler supports corruption type '\(type)'"
        }
    }
}
