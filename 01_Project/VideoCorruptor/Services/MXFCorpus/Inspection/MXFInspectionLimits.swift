import Foundation

struct MXFInspectionLimits: Equatable, Sendable {
    let maximumInputBytes: UInt64
    let maximumElementCount: UInt64
    let maximumBERValueLength: UInt64
    let maximumAllocationBytes: UInt64

    init(
        maximumInputBytes: UInt64 = 1 << 30,
        maximumElementCount: UInt64 = 1_000_000,
        maximumBERValueLength: UInt64 = 1 << 30,
        maximumAllocationBytes: UInt64 = 1 << 30
    ) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumElementCount = maximumElementCount
        self.maximumBERValueLength = maximumBERValueLength
        self.maximumAllocationBytes = maximumAllocationBytes
    }
}

enum MXFInspectionLimit: Equatable, Sendable {
    case inputBytes
    case elementCount
    case berValueLength
    case allocationBytes
}

enum MXFInspectionCheckpoint: Equatable, Sendable {
    case beforeInspection
    case beforeElement(offset: UInt64)
    case afterBER(offset: UInt64)
    case afterElement(offset: UInt64)
}

typealias MXFInspectionCancellationCheck = @Sendable (MXFInspectionCheckpoint) -> Bool
