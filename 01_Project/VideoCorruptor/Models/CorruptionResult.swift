import Foundation

/// Result of applying a single corruption to a source file.
struct CorruptionResult: Identifiable, Sendable {
    let id = UUID()
    let sourceFile: VideoFile
    let corruptionType: CorruptionType
    let outputURL: URL
    let outputSize: Int64
    let status: Status
    let detail: String

    enum Status: Sendable {
        case success
        case failed(String)
    }

    var isSuccess: Bool {
        if case .success = status { return true }
        return false
    }
}
