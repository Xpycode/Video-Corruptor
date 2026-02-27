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
    let seed: UInt64?
    let severity: CorruptionSeverity?
    let stackedTypes: [CorruptionType]?

    enum Status: Sendable {
        case success
        case failed(String)
    }

    var isSuccess: Bool {
        if case .success = status { return true }
        return false
    }

    init(
        sourceFile: VideoFile,
        corruptionType: CorruptionType,
        outputURL: URL,
        outputSize: Int64,
        status: Status,
        detail: String,
        seed: UInt64? = nil,
        severity: CorruptionSeverity? = nil,
        stackedTypes: [CorruptionType]? = nil
    ) {
        self.sourceFile = sourceFile
        self.corruptionType = corruptionType
        self.outputURL = outputURL
        self.outputSize = outputSize
        self.status = status
        self.detail = detail
        self.seed = seed
        self.severity = severity
        self.stackedTypes = stackedTypes
    }
}
