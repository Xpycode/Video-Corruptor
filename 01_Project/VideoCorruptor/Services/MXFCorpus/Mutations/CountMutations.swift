import Foundation

struct MXFCountFixtureDeclaration: Sendable {
    let profileID: String
    let setKey: Data
    let batchTag: UInt16
    let batchUniversalLabel: Data
    let batchItemOffset: UInt64
    let batchLengthEncodedWidth: UInt64
    let batchValueLength: UInt64
    let batchCount: UInt32
    let batchItemSize: UInt32
    let sliceDeltaTag: UInt16
    let sliceDeltaUniversalLabel: Data
    let sliceDeltaItemOffset: UInt64
    let sliceDeltaLengthEncodedWidth: UInt64
    let sliceDeltaValueLength: UInt64
    let sliceDeltaCount: UInt32
    let sliceDeltaItemSize: UInt32

    init(
        profileID: String,
        setKey: Data,
        batchTag: UInt16,
        batchUniversalLabel: Data,
        batchItemOffset: UInt64,
        batchLengthEncodedWidth: UInt64,
        batchValueLength: UInt64,
        batchCount: UInt32,
        batchItemSize: UInt32,
        sliceDeltaTag: UInt16,
        sliceDeltaUniversalLabel: Data,
        sliceDeltaItemOffset: UInt64,
        sliceDeltaLengthEncodedWidth: UInt64,
        sliceDeltaValueLength: UInt64,
        sliceDeltaCount: UInt32,
        sliceDeltaItemSize: UInt32
    ) throws {
        guard setKey.count == 16 else { throw MXFCountDeclarationError.invalidSetKeyWidth }
        guard batchUniversalLabel.count == MXFPrimerMap.universalLabelByteCount,
              sliceDeltaUniversalLabel.count == MXFPrimerMap.universalLabelByteCount else {
            throw MXFCountDeclarationError.invalidUniversalLabelWidth
        }
        guard (1...9).contains(batchLengthEncodedWidth),
              (1...9).contains(sliceDeltaLengthEncodedWidth) else {
            throw MXFCountDeclarationError.invalidBERWidth
        }
        self.profileID = profileID
        self.setKey = setKey
        self.batchTag = batchTag
        self.batchUniversalLabel = batchUniversalLabel
        self.batchItemOffset = batchItemOffset
        self.batchLengthEncodedWidth = batchLengthEncodedWidth
        self.batchValueLength = batchValueLength
        self.batchCount = batchCount
        self.batchItemSize = batchItemSize
        self.sliceDeltaTag = sliceDeltaTag
        self.sliceDeltaUniversalLabel = sliceDeltaUniversalLabel
        self.sliceDeltaItemOffset = sliceDeltaItemOffset
        self.sliceDeltaLengthEncodedWidth = sliceDeltaLengthEncodedWidth
        self.sliceDeltaValueLength = sliceDeltaValueLength
        self.sliceDeltaCount = sliceDeltaCount
        self.sliceDeltaItemSize = sliceDeltaItemSize
    }
}

enum MXFCountDeclarationError: Error, Equatable, Sendable {
    case invalidSetKeyWidth
    case invalidUniversalLabelWidth
    case invalidBERWidth
}

enum CountMutations {
    static func fixtures(declarations: [MXFCountFixtureDeclaration]) -> [any MXFFixtureMutation] {
        declarations.flatMap { declaration in
            CountMutationKind.allCases.map { CountMutation(kind: $0, declaration: declaration) }
        }
    }
}

private enum CountMutationKind: String, CaseIterable, Sendable {
    case localSetItemExceedsValue = "count.localSetItemExceedsValue.v1"
    case batchExceedsPayload = "count.batchExceedsPayload.v1"
    case batchItemSizeZero = "count.batchItemSizeZero.v1"
    case batchMultiplicationOverflow = "count.batchMultiplicationOverflow.v1"
    case sliceDeltaExtreme = "count.sliceDeltaExtreme.v1"
}

private enum CountMutationError: Error, Equatable, Sendable {
    case targetUnavailable(String)
    case shortRead(UInt64)
    case declaredPreconditionMismatch(String)
    case postconditionFailed(String)
}

private struct CountTarget: Sendable {
    let set: MXFInspectedElement
    let item: MXFLocalSetItem
    let fieldSpan: ByteSpan
    let original: UInt64
    let replacement: UInt64
    let classification: String
}

private struct CountMutation: MXFFixtureMutation {
    let kind: CountMutationKind
    let declaration: MXFCountFixtureDeclaration

    var definition: MXFFixtureDefinition {
        MXFFixtureDefinition(
            id: kind.rawValue,
            title: kind.rawValue,
            rationale: "Exercises bounded count and local-set validation without count-sized allocation.",
            corpusClass: .parserConformance,
            lifecycle: .draft,
            mutationSchemaVersion: 1,
            requiredSourceCharacteristics: [
                "declared synthetic profile \(declaration.profileID)",
                "exact local-set key and primer tag mapping"
            ],
            targetSelectionRule: "first complete declared set containing the exact declared tag and valid baseline field",
            parameters: ["sourceProfile": declaration.profileID],
            seed: nil,
            expectedStructuralCondition: structuralCondition,
            defaultExpectedResult: .init(outcome: .rejected, category: expectedCategory, consumerCode: nil),
            recommendedLimits: Self.limits
        )
    }

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        guard let target = target(in: source) else {
            return .notApplicable(reason: "no isolated target satisfies declared profile \(declaration.profileID)")
        }
        return .applicable(targetOffset: target.fieldSpan.lowerBound,
                           targetClassification: target.classification)
    }

    func apply(to workingFile: URL, source: MXFInspectedFile, rng: inout SeededRNG) throws -> MXFMutationRecord {
        guard let target = target(in: source) else { throw CountMutationError.targetUnavailable(kind.rawValue) }
        let width = target.fieldSpan.length
        let original = try read(file: workingFile, span: target.fieldSpan)
        let actual: UInt64
        if kind == .localSetItemExceedsValue {
            actual = try MXFBER.decodeHeader(original, atPhysicalOffset: target.fieldSpan.lowerBound).value
        } else {
            actual = UInt64(try original.checkedUInt32BE(at: 0))
        }
        guard actual == target.original else {
            throw CountMutationError.declaredPreconditionMismatch(fieldName)
        }
        let replacement = try encoded(target.replacement, width: width, ber: kind == .localSetItemExceedsValue)
        let field = fieldName
        let edit = try MXFMutationRecorder().recordEdit(offset: target.fieldSpan.lowerBound,
                                                        original: original, replacement: replacement,
                                                        field: field)
        try MXFEditApplicator().apply(edits: [edit], truncation: nil, to: workingFile)
        return MXFMutationRecord(
            targetOffset: MXFDecimalUInt64(target.fieldSpan.lowerBound),
            targetClassification: target.classification,
            edits: [edit], truncation: nil,
            semanticValues: [try MXFSemanticValue(field: field, kind: .unsigned,
                                                   original: String(target.original),
                                                   replacement: String(target.replacement))]
        )
    }

    func postconditions(for source: MXFInspectedFile) -> [MXFPostcondition] {
        guard let target = target(in: source), let enclosing = target.set.valueSpan else { return [] }
        return [{ context in
            let data = try Data(contentsOf: context.outputURL, options: .mappedIfSafe)
            let local = MXFLocalSetInspector().inspect(
                data: data, enclosingSpan: enclosing, primerMap: try self.primerMap,
                maximumItemCount: 32
            )
            if self.kind == .localSetItemExceedsValue {
                guard case .itemExceedsEnclosingValue(let tag, _, let declared, _) = local.error,
                      tag == target.item.tag, declared == target.replacement else {
                    throw CountMutationError.postconditionFailed("expected bounded local-set invalidLength")
                }
                return
            }
            guard local.completedWalk,
                  let item = local.items.first(where: { $0.tag == target.item.tag }),
                  let valueSpan = item.valueSpan else {
                throw CountMutationError.postconditionFailed("declared local item was not reinspected")
            }
            let result = MXFBatchInspector().inspect(batchSpan: valueSpan, in: data,
                                                     limits: self.postconditionLimits)
            guard self.matches(result) else {
                throw CountMutationError.postconditionFailed("unexpected bounded batch result: \(result)")
            }
        }]
    }

    private func target(in source: MXFInspectedFile) -> CountTarget? {
        guard let map = try? primerMap else { return nil }
        for set in source.elements where set.key == declaration.setKey {
            guard let enclosing = set.valueSpan else { continue }
            let wantedTag = kind == .sliceDeltaExtreme ? declaration.sliceDeltaTag : declaration.batchTag
            let relativeOffset = kind == .sliceDeltaExtreme ? declaration.sliceDeltaItemOffset : declaration.batchItemOffset
            let lengthWidth = kind == .sliceDeltaExtreme ? declaration.sliceDeltaLengthEncodedWidth : declaration.batchLengthEncodedWidth
            let valueLength = kind == .sliceDeltaExtreme ? declaration.sliceDeltaValueLength : declaration.batchValueLength
            let declaredCount = kind == .sliceDeltaExtreme ? declaration.sliceDeltaCount : declaration.batchCount
            let declaredItemSize = kind == .sliceDeltaExtreme ? declaration.sliceDeltaItemSize : declaration.batchItemSize
            guard map.universalLabel(for: wantedTag) != nil,
                  let tagOffset = try? CheckedBinaryArithmetic.add(enclosing.lowerBound, relativeOffset),
                  let berOffset = try? CheckedBinaryArithmetic.add(tagOffset, 2),
                  let valueOffset = try? CheckedBinaryArithmetic.add(berOffset, lengthWidth),
                  let valueEnd = try? CheckedBinaryArithmetic.add(valueOffset, valueLength),
                  valueEnd <= enclosing.upperBound,
                  let tagSpan = try? ByteSpan(offset: tagOffset, length: 2),
                  let physical = try? ByteSpan(lowerBound: tagOffset, upperBound: valueEnd),
                  let valueSpan = try? ByteSpan(lowerBound: valueOffset, upperBound: valueEnd),
                  let berPhysicalSpan = try? ByteSpan(offset: berOffset, length: lengthWidth) else { continue }
            let form: MXFBERForm = lengthWidth == 1 ? .short : .long(lengthOctetCount: UInt8(lengthWidth - 1))
            let ber = MXFBERDecodedLength(value: valueLength, encodedWidth: lengthWidth,
                                          physicalSpan: berPhysicalSpan, form: form,
                                          canonicality: .canonical, diagnostics: [])
            let item = MXFLocalSetItem(tag: wantedTag, resolvedUniversalLabel: map.universalLabel(for: wantedTag),
                                       tagSpan: tagSpan, ber: ber,
                                       valueSpan: valueLength == 0 ? nil : valueSpan, physicalSpan: physical)
            if kind == .localSetItemExceedsValue {
                let span = item.ber.physicalSpan
                let replacement = enclosing.upperBound - (span.upperBound) + 1
                guard replacement > item.ber.value, canEncodeBER(replacement, width: span.length) else { continue }
                return CountTarget(set: set, item: item, fieldSpan: span, original: item.ber.value,
                                   replacement: replacement, classification: classification(tag: wantedTag, field: "localItem.length"))
            }
            guard let value = item.valueSpan, value.length >= 8,
                  let countSpan = try? ByteSpan(offset: value.lowerBound, length: 4),
                  let sizeOffset = try? CheckedBinaryArithmetic.add(value.lowerBound, 4),
                  let sizeSpan = try? ByteSpan(offset: sizeOffset, length: 4),
                  let header = try? MXFBatchHeader(count: .init(value: UInt64(declaredCount), span: countSpan),
                                                   itemSize: .init(value: UInt64(declaredItemSize), span: sizeSpan)),
                  case .batch(let batch) = MXFBatchInspector().validate(
                    header: header, enclosingPayloadByteCount: value.length - 8,
                    physicalPayloadByteCount: value.length - 8,
                    limits: .init(maximumElementCount: .max, maximumAllocationBytes: .max)) else { continue }
            switch kind {
            case .batchExceedsPayload:
                guard batch.header.itemSize.value > 0 else { continue }
                let available = value.length - MXFBatchInspector.headerByteCount
                let replacement = available / batch.header.itemSize.value + 1
                guard replacement <= UInt64(UInt32.max), replacement != batch.header.count.value else { continue }
                return make(batch.header.count.span, batch.header.count.value, replacement, set, item, wantedTag, "batch.count")
            case .batchItemSizeZero:
                guard batch.header.count.value > 0, batch.header.itemSize.value != 0 else { continue }
                return make(batch.header.itemSize.span, batch.header.itemSize.value, 0, set, item, wantedTag, "batch.itemSize")
            case .batchMultiplicationOverflow:
                guard batch.header.itemSize.value > 0, batch.header.count.value != UInt64(UInt32.max) else { continue }
                return make(batch.header.count.span, batch.header.count.value, UInt64(UInt32.max), set, item, wantedTag, "batch.count")
            case .sliceDeltaExtreme:
                guard batch.header.count.value != UInt64(UInt32.max) else { continue }
                return make(batch.header.count.span, batch.header.count.value, UInt64(UInt32.max), set, item, wantedTag, "index.sliceDeltaCount")
            case .localSetItemExceedsValue:
                break
            }
        }
        return nil
    }

    private func make(_ span: ByteSpan, _ original: UInt64, _ replacement: UInt64,
                      _ set: MXFInspectedElement, _ item: MXFLocalSetItem, _ tag: UInt16,
                      _ field: String) -> CountTarget {
        CountTarget(set: set, item: item, fieldSpan: span, original: original, replacement: replacement,
                    classification: classification(tag: tag, field: field))
    }

    private var primerMap: MXFPrimerMap {
        get throws {
            try MXFPrimerMap(mappings: [
                declaration.batchTag: declaration.batchUniversalLabel,
                declaration.sliceDeltaTag: declaration.sliceDeltaUniversalLabel
            ])
        }
    }

    private func classification(tag: UInt16, field: String) -> String {
        String(format: "localSet:%@:tag.0x%04x:%@", declaration.profileID, tag, field)
    }

    private var fieldName: String {
        switch kind {
        case .localSetItemExceedsValue: return "localSet.itemLength"
        case .batchItemSizeZero: return "batch.itemSize"
        case .sliceDeltaExtreme: return "index.sliceDeltaCount"
        default: return "batch.count"
        }
    }

    private var expectedCategory: String {
        switch kind {
        case .localSetItemExceedsValue: return "invalidLength"
        case .batchExceedsPayload, .batchItemSizeZero: return "invalidCount"
        case .batchMultiplicationOverflow, .sliceDeltaExtreme: return "limitExceeded"
        }
    }

    private var structuralCondition: String { expectedCategory }

    private var postconditionLimits: MXFInspectionLimits {
        switch kind {
        case .batchMultiplicationOverflow, .sliceDeltaExtreme:
            return .init(maximumElementCount: 1_000, maximumAllocationBytes: 1_024)
        default:
            return .init(maximumElementCount: .max, maximumAllocationBytes: .max)
        }
    }

    private func matches(_ result: MXFBatchInspectionResult) -> Bool {
        switch (kind, result) {
        case (.batchExceedsPayload, .invalid(.payloadExceedsEnclosingSpan)): return true
        case (.batchItemSizeZero, .invalid(.zeroItemSizeWithNonzeroCount)): return true
        case (.batchMultiplicationOverflow, .invalid(.limitExceeded(_, .elementCount, _, _))): return true
        case (.sliceDeltaExtreme, .invalid(.limitExceeded(_, .elementCount, _, _))): return true
        default: return false
        }
    }

    private func read(file: URL, span: ByteSpan) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: span.lowerBound)
        let count = try CheckedBinaryArithmetic.int(exactly: span.length)
        let bytes = try handle.read(upToCount: count) ?? Data()
        guard bytes.count == count else { throw CountMutationError.shortRead(span.lowerBound) }
        return bytes
    }

    private func encoded(_ value: UInt64, width: UInt64, ber: Bool) throws -> Data {
        let count = try CheckedBinaryArithmetic.int(exactly: width)
        if ber {
            if width == 1 { return Data([UInt8(value)]) }
            var bytes = Data(repeating: 0, count: count)
            bytes[0] = 0x80 | UInt8(width - 1)
            var remaining = value
            for index in stride(from: count - 1, through: 1, by: -1) {
                bytes[index] = UInt8(remaining & 0xff)
                remaining >>= 8
            }
            return bytes
        }
        var bytes = Data(repeating: 0, count: count)
        try bytes.checkedWriteUInt32BE(UInt32(value), at: 0)
        return bytes
    }

    private func canEncodeBER(_ value: UInt64, width: UInt64) -> Bool {
        if width == 1 { return value < 0x80 }
        let octets = width - 1
        return octets >= 8 || value < (UInt64(1) << (octets * 8))
    }

    private static let limits = MXFReaderLimits(
        maxInputBytes: .init(64 * 1_024 * 1_024), maxKLVElements: .init(100_000),
        maxBERValueLength: .init(32 * 1_024 * 1_024), maxAllocationBytes: .init(1_024),
        maxLocalSetItems: .init(32), maxPartitionHops: .init(128), maxVisitedOffsets: .init(128)
    )
}
