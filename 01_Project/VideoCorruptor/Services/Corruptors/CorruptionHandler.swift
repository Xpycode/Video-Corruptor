import Foundation

/// Protocol for format-specific corruption implementations.
/// Each handler owns a set of corruption types and knows how to apply them.
protocol CorruptionHandler: Sendable {
    /// The corruption types this handler can apply.
    var supportedTypes: Set<CorruptionType> { get }

    /// Apply a corruption to a copied file.
    /// - Parameters:
    ///   - type: The corruption to apply.
    ///   - url: The output file (already copied from source).
    ///   - sourceFile: The original source file metadata.
    func apply(_ type: CorruptionType, to url: URL, sourceFile: VideoFile) throws
}
