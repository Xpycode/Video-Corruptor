import Foundation

/// Handles format-agnostic file-level corruptions.
struct FileCorruptor: CorruptionHandler {

    let supportedTypes: Set<CorruptionType> = [
        .truncation, .zeroByteFile, .fakeExtension
    ]

    func apply(_ type: CorruptionType, to url: URL, sourceFile: VideoFile) throws {
        switch type {
        case .truncation:
            try applyTruncation(to: url)
        case .zeroByteFile, .fakeExtension:
            break // Handled by engine before copy
        default:
            break
        }
    }

    /// Cut file at 60% of its length.
    private func applyTruncation(to url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        let size = handle.seekToEndOfFile()
        let cutPoint = UInt64(Double(size) * 0.6)
        handle.truncateFile(atOffset: cutPoint)
    }
}
