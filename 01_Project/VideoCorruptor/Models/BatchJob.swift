import Foundation

/// A single batch processing job for one source file.
struct BatchJob: Identifiable, Sendable {
    let id = UUID()
    let sourceFile: VideoFile
    var status: BatchJobStatus = .pending
    var progress: Double = 0
    var results: [CorruptionResult] = []

    enum BatchJobStatus: Sendable {
        case pending
        case processing
        case completed
        case failed(String)
        case cancelled
    }

    var isComplete: Bool {
        switch status {
        case .completed, .failed, .cancelled: true
        default: false
        }
    }

    var statusLabel: String {
        switch status {
        case .pending: "Pending"
        case .processing: "Processing..."
        case .completed: "Complete"
        case .failed(let msg): "Failed: \(msg)"
        case .cancelled: "Cancelled"
        }
    }
}
