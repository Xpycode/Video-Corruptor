import Foundation

enum MXFGenericTruncationKind: String, CaseIterable, Hashable, Sendable {
    case insideKey
    case immediatelyPostKey
    case insideLongBER
    case immediatelyPostLongBER
    case oneByteBeforeValueEnd
    case betweenCompleteKLVTriplets
    case insidePartitionFixedField
}

enum MXFTruncationMutationError: Error, Equatable, Sendable {
    case preconditionChanged(String)
}

struct MXFGenericTruncationMutation: MXFFixtureMutation, Sendable {
    let kind: MXFGenericTruncationKind

    var definition: MXFFixtureDefinition {
        let result: MXFExpectedResult
        switch kind {
        case .betweenCompleteKLVTriplets:
            result = MXFExpectedResult(
                outcome: .acceptedWithWarning,
                category: "cleanEndBeforeRemainingKLVs",
                consumerCode: nil
            )
        case .insidePartitionFixedField:
            result = MXFExpectedResult(
                outcome: .rejected,
                category: "unexpectedEOF",
                consumerCode: nil
            )
        default:
            result = MXFExpectedResult(
                outcome: .rejected,
                category: "unexpectedEOF",
                consumerCode: nil
            )
        }

        return MXFFixtureDefinition(
            id: fixtureID,
            title: title,
            rationale: rationale,
            corpusClass: .parserConformance,
            lifecycle: .draft,
            mutationSchemaVersion: 1,
            requiredSourceCharacteristics: [requiredCharacteristic],
            targetSelectionRule: selectionRule,
            parameters: ["boundary": boundary],
            seed: nil,
            expectedStructuralCondition: structuralCondition,
            defaultExpectedResult: result,
            recommendedLimits: Self.readerLimits
        )
    }

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        guard let target = target(in: source) else {
            return .notApplicable(reason: notApplicableReason)
        }
        return .applicable(
            targetOffset: target.elementOffset,
            targetClassification: target.classification
        )
    }

    func apply(
        to workingFile: URL,
        source: MXFInspectedFile,
        rng: inout SeededRNG
    ) throws -> MXFMutationRecord {
        _ = rng
        guard let target = target(in: source) else {
            throw MXFTruncationMutationError.preconditionChanged(notApplicableReason)
        }
        let truncation = try MXFTruncationRecord(
            originalSize: source.inputByteCount,
            retainedSize: target.retainedSize,
            containingElement: target.containingElement,
            boundary: boundary
        )
        let handle = try FileHandle(forUpdating: workingFile)
        defer { try? handle.close() }
        try handle.truncate(atOffset: target.retainedSize)

        return MXFMutationRecord(
            targetOffset: MXFDecimalUInt64(target.elementOffset),
            targetClassification: target.classification,
            edits: [],
            truncation: truncation,
            semanticValues: []
        )
    }

    private struct Target: Sendable {
        let retainedSize: UInt64
        let elementOffset: UInt64
        let classification: String
        let containingElement: String?
    }

    private func target(in source: MXFInspectedFile) -> Target? {
        switch kind {
        case .insideKey:
            guard let element = source.elements.first,
                  let retained = checkedAdd(element.keySpan.lowerBound, 8),
                  retained < source.inputByteCount else { return nil }
            return elementTarget(element, retained: retained, classification: "KLV key")

        case .immediatelyPostKey:
            guard let element = source.elements.first,
                  element.keySpan.upperBound < source.inputByteCount else { return nil }
            return elementTarget(element, retained: element.keySpan.upperBound, classification: "post-KLV key")

        case .insideLongBER:
            guard let element = source.elements.first(where: { isLongBER($0.ber) }),
                  let retained = checkedAdd(element.ber.physicalSpan.lowerBound, 1),
                  retained < element.ber.physicalSpan.upperBound else { return nil }
            return elementTarget(element, retained: retained, classification: "long-form BER")

        case .immediatelyPostLongBER:
            guard let element = source.elements.first(where: { isLongBER($0.ber) }),
                  element.ber.physicalSpan.upperBound < source.inputByteCount else { return nil }
            return elementTarget(
                element,
                retained: element.ber.physicalSpan.upperBound,
                classification: "post-long-form BER"
            )

        case .oneByteBeforeValueEnd:
            guard let element = source.elements.first(where: { ($0.valueSpan?.length ?? 0) > 0 }),
                  let valueSpan = element.valueSpan,
                  valueSpan.upperBound > 0 else { return nil }
            let retained = valueSpan.upperBound - 1
            guard retained < source.inputByteCount else { return nil }
            return elementTarget(element, retained: retained, classification: "KLV value")

        case .betweenCompleteKLVTriplets:
            guard source.elements.count >= 2 else { return nil }
            for index in 0..<(source.elements.count - 1) {
                let element = source.elements[index]
                let next = source.elements[index + 1]
                let retained = element.physicalSpan.upperBound
                if retained == next.physicalSpan.lowerBound, retained < source.inputByteCount {
                    return Target(
                        retainedSize: retained,
                        elementOffset: element.keySpan.lowerBound,
                        classification: "complete KLV triplet boundary",
                        containingElement: elementDescription(element)
                    )
                }
            }
            return nil

        case .insidePartitionFixedField:
            let inspector = MXFPartitionInspector()
            for element in source.elements {
                guard inspector.classify(key: element.key) != nil,
                      let valueSpan = element.valueSpan,
                      valueSpan.length >= MXFPartitionInspector.fixedValueByteCount,
                      let fieldEnd = checkedAdd(valueSpan.lowerBound, 16),
                      fieldEnd <= source.inputByteCount else { continue }
                return elementTarget(
                    element,
                    retained: fieldEnd - 1,
                    classification: "partition fixed field: thisPartition"
                )
            }
            return nil
        }
    }

    private func elementTarget(
        _ element: MXFInspectedElement,
        retained: UInt64,
        classification: String
    ) -> Target {
        Target(
            retainedSize: retained,
            elementOffset: element.keySpan.lowerBound,
            classification: classification,
            containingElement: elementDescription(element)
        )
    }

    private func elementDescription(_ element: MXFInspectedElement) -> String {
        "KLV at byte \(element.keySpan.lowerBound)"
    }

    private func isLongBER(_ ber: MXFBERDecodedLength) -> Bool {
        if case .long = ber.form { return true }
        return false
    }

    private func checkedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64? {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : result
    }

    private static let readerLimits = MXFReaderLimits(
        maxInputBytes: MXFDecimalUInt64(1 << 30),
        maxKLVElements: MXFDecimalUInt64(1_000_000),
        maxBERValueLength: MXFDecimalUInt64(1 << 30),
        maxAllocationBytes: MXFDecimalUInt64(64 << 20),
        maxLocalSetItems: MXFDecimalUInt64(100_000),
        maxPartitionHops: MXFDecimalUInt64(10_000),
        maxVisitedOffsets: MXFDecimalUInt64(100_000)
    )

    private var fixtureID: String {
        "mxf.truncation.\(kind.rawValue).v1"
    }

    private var title: String {
        switch kind {
        case .insideKey: "Truncate inside a KLV key"
        case .immediatelyPostKey: "Truncate immediately after a KLV key"
        case .insideLongBER: "Truncate inside a long-form BER field"
        case .immediatelyPostLongBER: "Truncate immediately after a long-form BER field"
        case .oneByteBeforeValueEnd: "Truncate one byte before a KLV value ends"
        case .betweenCompleteKLVTriplets: "Truncate between complete KLV triplets"
        case .insidePartitionFixedField: "Truncate inside a partition pack fixed field"
        }
    }

    private var rationale: String {
        kind == .betweenCompleteKLVTriplets
            ? "Proves that a structurally clean prefix is not mislabeled as an unexpected EOF."
            : "Exercises bounded parsing at a structurally derived incomplete KLV boundary."
    }

    private var requiredCharacteristic: String {
        switch kind {
        case .insideKey, .immediatelyPostKey: "At least one complete KLV triplet"
        case .insideLongBER, .immediatelyPostLongBER: "At least one complete KLV with long-form BER"
        case .oneByteBeforeValueEnd: "At least one complete KLV with a nonempty value"
        case .betweenCompleteKLVTriplets: "At least two physically adjacent complete KLV triplets"
        case .insidePartitionFixedField: "At least one complete partition pack fixed field"
        }
    }

    private var selectionRule: String {
        switch kind {
        case .insideLongBER, .immediatelyPostLongBER: "Lowest-offset complete KLV using long-form BER"
        case .oneByteBeforeValueEnd: "Lowest-offset complete KLV with a nonempty value"
        case .betweenCompleteKLVTriplets: "Lowest-offset adjacent pair of complete KLV triplets"
        case .insidePartitionFixedField: "Lowest-offset complete partition pack; ThisPartition field"
        default: "Lowest-offset complete KLV triplet"
        }
    }

    private var boundary: String {
        switch kind {
        case .insideKey: "inside 16-byte KLV key after 8 bytes"
        case .immediatelyPostKey: "immediately after complete 16-byte KLV key"
        case .insideLongBER: "inside long-form BER after its first octet"
        case .immediatelyPostLongBER: "immediately after complete long-form BER field"
        case .oneByteBeforeValueEnd: "one byte before declared KLV value end"
        case .betweenCompleteKLVTriplets: "between physically adjacent complete KLV triplets"
        case .insidePartitionFixedField: "inside partition pack ThisPartition fixed field, one byte before its end"
        }
    }

    private var structuralCondition: String {
        kind == .betweenCompleteKLVTriplets
            ? "Output is an exact source prefix ending after a complete KLV triplet."
            : "Output is an exact source prefix ending inside an otherwise complete KLV triplet."
    }

    private var notApplicableReason: String {
        "Source lacks required boundary: \(boundary)"
    }
}

enum MXFTruncationMutations {
    static let all: [MXFGenericTruncationMutation] = MXFGenericTruncationKind.allCases.map {
        MXFGenericTruncationMutation(kind: $0)
    }
}
