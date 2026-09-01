import Foundation

enum MXFRequiredElementDeclarationError: Error, Equatable, Sendable {
    case invalidKeyWidth(Int)
    case emptyProfileID
    case emptyClassification
}

/// A controlled source/profile assertion. No MXF key is treated as required unless the caller
/// supplies one of these declarations, and the zero-length boundary policy is verified afterward.
struct MXFRequiredElementDeclaration: Equatable, Sendable {
    enum ZeroLengthBoundaryPolicy: Equatable, Sendable {
        case payloadStartsCompleteKLVSequence
    }

    let profileID: String
    let key: Data
    let classification: String
    let zeroLengthBoundaryPolicy: ZeroLengthBoundaryPolicy

    init(
        profileID: String,
        key: Data,
        classification: String,
        zeroLengthBoundaryPolicy: ZeroLengthBoundaryPolicy
    ) throws {
        guard key.count == 16 else {
            throw MXFRequiredElementDeclarationError.invalidKeyWidth(key.count)
        }
        guard !profileID.isEmpty else { throw MXFRequiredElementDeclarationError.emptyProfileID }
        guard !classification.isEmpty else {
            throw MXFRequiredElementDeclarationError.emptyClassification
        }
        self.profileID = profileID
        self.key = key
        self.classification = classification
        self.zeroLengthBoundaryPolicy = zeroLengthBoundaryPolicy
    }
}

enum BERMutations {
    static let fixtures: [any MXFFixtureMutation] = fixtures(requiredElements: [])

    static func fixtures(
        requiredElements: [MXFRequiredElementDeclaration]
    ) -> [any MXFFixtureMutation] {
        BERMutationKind.allCases.map {
            BERMutation(kind: $0, requiredElements: requiredElements)
        }
    }
}

private enum BERMutationKind: String, CaseIterable, Sendable {
    case indefiniteForm = "ber.indefiniteForm.v1"
    case lengthOfLengthTooLarge = "ber.lengthOfLengthTooLarge.v1"
    case headerTruncated = "ber.headerTruncated.v1"
    case valueBeyondEOF = "ber.valueBeyondEOF.v1"
    case lengthAdditionOverflow = "ber.lengthAdditionOverflow.v1"
    case nonMinimalLongForm = "ber.nonMinimalLongForm.v1"
    case zeroRequiredValue = "ber.zeroRequiredValue.v1"
    case shorterThanPayload = "ber.shorterThanPayload.v1"
}

private enum BERMutationError: Error, Equatable, Sendable {
    case evaluatedTargetUnavailable(String)
    case invalidSourceSpan(UInt64)
    case postconditionFailed(String)
}

private struct BERMutation: MXFFixtureMutation {
    let kind: BERMutationKind
    let requiredElements: [MXFRequiredElementDeclaration]

    var definition: MXFFixtureDefinition {
        MXFFixtureDefinition(
            id: kind.rawValue,
            title: title,
            rationale: rationale,
            corpusClass: .parserConformance,
            lifecycle: .draft,
            mutationSchemaVersion: 1,
            requiredSourceCharacteristics: [requiredCharacteristic],
            targetSelectionRule: targetRule,
            parameters: [:],
            seed: nil,
            expectedStructuralCondition: structuralCondition,
            defaultExpectedResult: expectedResult,
            recommendedLimits: Self.limits
        )
    }

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        guard let target = target(in: source) else {
            return .notApplicable(reason: notApplicableReason)
        }
        return .applicable(
            targetOffset: target.ber.physicalSpan.lowerBound,
            targetClassification: targetClassification(for: target)
        )
    }

    func apply(
        to workingFile: URL,
        source: MXFInspectedFile,
        rng: inout SeededRNG
    ) throws -> MXFMutationRecord {
        guard let target = target(in: source) else {
            throw BERMutationError.evaluatedTargetUnavailable(kind.rawValue)
        }
        let recorder = MXFMutationRecorder()
        let berOffset = target.ber.physicalSpan.lowerBound
        var edits: [MXFByteEdit] = []
        var truncation: MXFTruncationRecord?
        var semanticValues: [MXFSemanticValue] = []

        switch kind {
        case .indefiniteForm:
            edits = [try edit(workingFile, at: berOffset, replacement: Data([0x80]), recorder: recorder)]
        case .lengthOfLengthTooLarge:
            edits = [try edit(workingFile, at: berOffset, replacement: Data([0x89]), recorder: recorder)]
        case .headerTruncated:
            let retained = try CheckedBinaryArithmetic.add(berOffset, target.ber.encodedWidth - 1)
            truncation = try MXFTruncationRecord(
                originalSize: source.inputByteCount,
                retainedSize: retained,
                containingElement: "KLV at \(target.keySpan.lowerBound)",
                boundary: "inside long-form BER header"
            )
        case .valueBeyondEOF:
            let valueOffset = try CheckedBinaryArithmetic.add(berOffset, target.ber.encodedWidth)
            let available = source.inputByteCount - valueOffset
            let replacementValue = try CheckedBinaryArithmetic.add(available, 1)
            let replacement = try encode(value: replacementValue, preserving: target.ber)
            edits = [try edit(workingFile, at: berOffset, replacement: replacement, recorder: recorder)]
            semanticValues = [try semantic(from: target.ber.value, to: replacementValue)]
        case .lengthAdditionOverflow:
            let replacement = Data([0x88]) + Data(repeating: 0xff, count: 8)
            edits = [try edit(workingFile, at: berOffset, replacement: replacement, recorder: recorder)]
            semanticValues = [try semantic(from: target.ber.value, to: .max)]
        case .nonMinimalLongForm:
            // The first payload byte becomes the long-form value octet. The value is shortened
            // by one, so the physical endpoint and all following KLV boundaries remain unchanged.
            let replacementValue = target.ber.value - 1
            let replacement = Data([0x81, UInt8(replacementValue)])
            edits = [try edit(workingFile, at: berOffset, replacement: replacement, recorder: recorder)]
            semanticValues = [try semantic(from: target.ber.value, to: replacementValue)]
        case .zeroRequiredValue:
            edits = [try edit(workingFile, at: berOffset, replacement: Data([0x00]), recorder: recorder)]
            semanticValues = [try semantic(from: target.ber.value, to: 0)]
        case .shorterThanPayload:
            let replacementValue = target.ber.value - 1
            let replacement = try encode(value: replacementValue, preserving: target.ber)
            edits = [try edit(workingFile, at: berOffset, replacement: replacement, recorder: recorder)]
            semanticValues = [try semantic(from: target.ber.value, to: replacementValue)]
        }

        try MXFEditApplicator().apply(edits: edits, truncation: truncation, to: workingFile)
        return MXFMutationRecord(
            targetOffset: MXFDecimalUInt64(berOffset),
            targetClassification: targetClassification(for: target),
            edits: edits,
            truncation: truncation,
            semanticValues: semanticValues
        )
    }

    func postconditions(for source: MXFInspectedFile) -> [MXFPostcondition] {
        let expectedOffset = target(in: source)?.ber.physicalSpan.lowerBound
        return [{ context in
            guard let expectedOffset else {
                throw BERMutationError.evaluatedTargetUnavailable(kind.rawValue)
            }
            let inspectionLimits = kind == .lengthAdditionOverflow
                ? MXFInspectionLimits(
                    maximumInputBytes: .max,
                    maximumElementCount: .max,
                    maximumBERValueLength: .max,
                    maximumAllocationBytes: .max
                )
                : MXFInspectionLimits()
            let result = try MXFStructuralInspector().inspect(
                fileAt: context.outputURL,
                limits: inspectionLimits
            )
            let diagnostics = result.diagnostics.filter {
                if case .nonCanonicalBER = $0 { return true }
                if case .malformedBER = $0 { return true }
                if case .truncatedValue = $0 { return true }
                if case .truncatedKey = $0 { return true }
                if case .integerOverflow = $0 { return true }
                if case .limitExceeded = $0 { return true }
                return false
            }
            if kind == .zeroRequiredValue {
                guard result.completedWalk,
                      result.elements.contains(where: {
                          $0.ber.physicalSpan.lowerBound == expectedOffset && $0.ber.value == 0
                      }) else {
                    throw BERMutationError.postconditionFailed(
                        "\(kind.rawValue): zero value did not leave a complete KLV walk"
                    )
                }
            }
            guard self.matches(diagnostics: diagnostics, at: expectedOffset) else {
                throw BERMutationError.postconditionFailed("\(kind.rawValue): \(diagnostics)")
            }
        }]
    }

    private func target(in source: MXFInspectedFile) -> MXFInspectedElement? {
        switch kind {
        case .indefiniteForm, .lengthOfLengthTooLarge:
            return source.elements.first
        case .headerTruncated:
            return source.elements.first { $0.ber.encodedWidth > 1 }
        case .valueBeyondEOF:
            return source.elements.reversed().first { element in
                guard let valueOffset = try? CheckedBinaryArithmetic.add(
                    element.ber.physicalSpan.lowerBound, element.ber.encodedWidth
                ) else { return false }
                let available = source.inputByteCount - valueOffset
                guard let replacement = try? CheckedBinaryArithmetic.add(available, 1) else { return false }
                return canEncode(value: replacement, preserving: element.ber)
            }
        case .lengthAdditionOverflow:
            return source.elements.first { $0.ber.encodedWidth == 9 }
        case .nonMinimalLongForm:
            return source.elements.first {
                $0.ber.encodedWidth == 1 && (2...127).contains($0.ber.value)
            }
        case .zeroRequiredValue:
            return source.elements.first { element in
                element.ber.encodedWidth == 1 && element.ber.value > 0
                    && requiredDeclaration(for: element) != nil
            }
        case .shorterThanPayload:
            return source.elements.reversed().first {
                $0.ber.value > 0 && canEncode(value: $0.ber.value - 1, preserving: $0.ber)
            }
        }
    }

    private func matches(diagnostics: [MXFStructuralDiagnostic], at offset: UInt64) -> Bool {
        switch kind {
        case .indefiniteForm:
            return diagnostics == [.malformedBER(offset: offset, error: .reservedIndefiniteForm(offset: offset))]
        case .lengthOfLengthTooLarge:
            return diagnostics == [.malformedBER(offset: offset, error: .excessiveLengthOfLength(
                offset: offset, lengthOctetCount: 9, maximum: 8
            ))]
        case .headerTruncated:
            guard diagnostics.count == 1,
                  case .malformedBER(let actualOffset, .truncatedHeader(let errorOffset, _, _)) = diagnostics[0]
            else { return false }
            return actualOffset == offset && errorOffset == offset
        case .valueBeyondEOF:
            return diagnostics.count == 1 && diagnostics.contains { if case .truncatedValue = $0 { true } else { false } }
        case .lengthAdditionOverflow:
            guard let valueOffset = try? CheckedBinaryArithmetic.add(offset, 9) else { return false }
            return diagnostics == [.integerOverflow(offset: valueOffset, operation: .valueEnd)]
        case .nonMinimalLongForm:
            return diagnostics == [.nonCanonicalBER(
                offset: offset,
                diagnostic: .nonMinimalLongForm(minimumLengthOctetCount: 1, actualLengthOctetCount: 1)
            )]
        case .zeroRequiredValue:
            return diagnostics.isEmpty
        case .shorterThanPayload:
            return diagnostics.count == 1 && diagnostics.contains { if case .truncatedKey = $0 { true } else { false } }
        }
    }

    private func edit(
        _ fileURL: URL,
        at offset: UInt64,
        replacement: Data,
        recorder: MXFMutationRecorder
    ) throws -> MXFByteEdit {
        let byteCount = try CheckedBinaryArithmetic.uint64(exactly: replacement.count)
        let span = try ByteSpan(offset: offset, length: byteCount)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard span.upperBound <= fileSize else { throw BERMutationError.invalidSourceSpan(offset) }
        try handle.seek(toOffset: span.lowerBound)
        guard let original = try handle.read(upToCount: replacement.count),
              original.count == replacement.count else {
            throw BERMutationError.invalidSourceSpan(offset)
        }
        return try recorder.recordEdit(
            offset: offset,
            original: original,
            replacement: replacement,
            field: "klv.valueLength"
        )
    }

    private func semantic(from original: UInt64, to replacement: UInt64) throws -> MXFSemanticValue {
        try MXFSemanticValue(
            field: "klv.valueLength", kind: .unsigned,
            original: String(original), replacement: String(replacement)
        )
    }

    private func encode(value: UInt64, preserving ber: MXFBERDecodedLength) throws -> Data {
        if ber.encodedWidth == 1 {
            guard value < 0x80 else { throw BERMutationError.evaluatedTargetUnavailable(kind.rawValue) }
            return Data([UInt8(value)])
        }
        let count = Int(ber.encodedWidth - 1)
        var bytes = Data([0x80 | UInt8(count)])
        for shift in stride(from: (count - 1) * 8, through: 0, by: -8) {
            bytes.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
        return bytes
    }

    private func canEncode(value: UInt64, preserving ber: MXFBERDecodedLength) -> Bool {
        if ber.encodedWidth == 1 { return value < 0x80 }
        let contentBytes = ber.encodedWidth - 1
        return contentBytes == 8 || value < (UInt64(1) << (contentBytes * 8))
    }

    private func targetClassification(for element: MXFInspectedElement) -> String {
        guard kind == .zeroRequiredValue,
              let declaration = requiredDeclaration(for: element) else {
            return "klv.ber.valueLength"
        }
        return "profile.requiredElement:\(declaration.profileID):\(declaration.classification)"
    }

    private func requiredDeclaration(
        for element: MXFInspectedElement
    ) -> MXFRequiredElementDeclaration? {
        let matches = requiredElements.filter {
            $0.key == element.key
                && $0.zeroLengthBoundaryPolicy == .payloadStartsCompleteKLVSequence
        }
        // Multiple profile claims for one physical key are ambiguous without richer source-profile
        // metadata, so they are conservatively rejected instead of depending on declaration order.
        return matches.count == 1 ? matches[0] : nil
    }

    private static let limits = MXFReaderLimits(
        maxInputBytes: MXFDecimalUInt64(16 * 1_024 * 1_024),
        maxKLVElements: MXFDecimalUInt64(100_000),
        maxBERValueLength: MXFDecimalUInt64.maxValue,
        maxAllocationBytes: MXFDecimalUInt64.maxValue,
        maxLocalSetItems: MXFDecimalUInt64(100_000),
        maxPartitionHops: MXFDecimalUInt64(1_024),
        maxVisitedOffsets: MXFDecimalUInt64(100_000)
    )

    private var title: String { "Malformed BER: \(kind.rawValue)" }
    private var rationale: String { "Exercises one bounded-reader BER framing invariant." }
    private var requiredCharacteristic: String {
        switch kind {
        case .headerTruncated: return "complete KLV with long-form BER"
        case .lengthAdditionOverflow: return "complete KLV with nine-byte BER encoding"
        case .nonMinimalLongForm: return "complete KLV with short-form length 2...127"
        case .zeroRequiredValue:
            return "controlled profile declaration for a required, nonempty, short-form element whose payload starts a complete KLV sequence"
        case .valueBeyondEOF: return "last complete KLV whose BER width can encode EOF+1"
        case .shorterThanPayload: return "last nonempty complete KLV"
        default: return "at least one complete KLV"
        }
    }
    private var targetRule: String { "lowest qualifying structural KLV offset (last qualifying KLV where EOF isolation is required)" }
    private var structuralCondition: String { kind.rawValue }
    private var notApplicableReason: String { "no complete KLV satisfies \(requiredCharacteristic)" }
    private var expectedResult: MXFExpectedResult {
        switch kind {
        case .headerTruncated: return .init(outcome: .rejected, category: "unexpectedEOF", consumerCode: nil)
        case .valueBeyondEOF, .zeroRequiredValue, .shorterThanPayload:
            return .init(outcome: .rejected, category: "invalidLength", consumerCode: nil)
        case .lengthAdditionOverflow: return .init(outcome: .rejected, category: "integerOverflow", consumerCode: nil)
        case .nonMinimalLongForm: return .init(outcome: .acceptedWithWarning, category: "nonCanonicalBER", consumerCode: nil)
        default: return .init(outcome: .rejected, category: "invalidBER", consumerCode: nil)
        }
    }
}

private extension MXFDecimalUInt64 {
    static let maxValue = MXFDecimalUInt64(UInt64.max)
}
