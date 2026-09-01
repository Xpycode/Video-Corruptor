import Foundation

struct MXFInspectedElement: Equatable, Sendable {
    let key: Data
    let keySpan: ByteSpan
    let ber: MXFBERDecodedLength
    let valueSpan: ByteSpan?
    let physicalSpan: ByteSpan
}

enum MXFPartialElement: Equatable, Sendable {
    case truncatedKey(offset: UInt64, availableSpan: ByteSpan?)
    case malformedBER(keySpan: ByteSpan, berOffset: UInt64)
    case truncatedValue(
        keySpan: ByteSpan,
        ber: MXFBERDecodedLength,
        valueOffset: UInt64,
        availableValueSpan: ByteSpan?
    )
}

struct MXFInspectionCounters: Equatable, Sendable {
    let candidateCount: UInt64
    let completeElementCount: UInt64
    let inspectedByteCount: UInt64
}

struct MXFInspectedFile: Equatable, Sendable {
    let inputByteCount: UInt64
    let trustedStartOffset: UInt64
    let elements: [MXFInspectedElement]
    let partialElement: MXFPartialElement?
    let counters: MXFInspectionCounters
    let diagnostics: [MXFStructuralDiagnostic]
    let completedWalk: Bool
}
