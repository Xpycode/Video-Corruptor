import Foundation

/// Handles format-agnostic file-level corruptions.
struct FileCorruptor: CorruptionHandler {

    let supportedTypes: Set<CorruptionType> = [
        .truncation, .zeroByteFile, .fakeExtension
    ]

    func apply(_ type: CorruptionType, to url: URL, sourceFile: VideoFile, context: inout CorruptionContext) throws {
        switch type {
        case .truncation:
            try applyTruncation(to: url, context: context)
        case .zeroByteFile, .fakeExtension:
            break // Handled by engine before copy
        default:
            break
        }
    }

    /// Truncate file. Severity: keep 95% (subtle) -> 1% (extreme).
    private func applyTruncation(to url: URL, context: CorruptionContext) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        let size = handle.seekToEndOfFile()
        // Severity: keep 95% at 0.0 intensity, keep 1% at 1.0 intensity
        let keepFraction = 0.95 - context.severity.intensity * 0.94
        let cutPoint = UInt64(Double(size) * keepFraction)
        handle.truncateFile(atOffset: cutPoint)
    }
}
