import Foundation

/// Fixture-owned description of an index table segment. Operational MXF tags are never inferred.
struct MXFIndexFixtureDeclaration: Sendable {
    let profileID: String
    let setKey: Data
    let tags: [UInt16: MXFIndexTableField]
    let universalLabels: [UInt16: Data]
    /// Offsets are relative to the beginning of the local-set value and point at each item's tag.
    let itemOffsets: [MXFIndexTableField: UInt64]
    let itemLengthEncodedWidths: [MXFIndexTableField: UInt64]
    let baselineStreamOffsets: [UInt64]
    let indexEntryValueLength: UInt64
    let indexEntryItemSize: UInt32
    let expectedIndexSID: UInt32
    let expectedBodySID: UInt32
    let essenceStreamSpan: ByteSpan

    init(
        profileID: String,
        setKey: Data,
        tags: [UInt16: MXFIndexTableField],
        universalLabels: [UInt16: Data],
        itemOffsets: [MXFIndexTableField: UInt64],
        itemLengthEncodedWidths: [MXFIndexTableField: UInt64],
        baselineStreamOffsets: [UInt64],
        indexEntryValueLength: UInt64,
        indexEntryItemSize: UInt32,
        expectedIndexSID: UInt32,
        expectedBodySID: UInt32,
        essenceStreamSpan: ByteSpan
    ) throws {
        guard setKey.count == 16 else { throw MXFIndexFixtureDeclarationError.invalidSetKeyWidth }
        guard Set(tags.keys) == Set(universalLabels.keys),
              universalLabels.values.allSatisfy({ $0.count == MXFPrimerMap.universalLabelByteCount }) else {
            throw MXFIndexFixtureDeclarationError.invalidTagSchema
        }
        guard Set(tags.values) == Set(MXFIndexTableField.allCases),
              Set(itemOffsets.keys) == Set(MXFIndexTableField.allCases),
              Set(itemLengthEncodedWidths.keys) == Set(MXFIndexTableField.allCases),
              itemLengthEncodedWidths.values.allSatisfy({ (1...9).contains($0) }) else {
            throw MXFIndexFixtureDeclarationError.incompleteFieldSchema
        }
        _ = try MXFIndexTableFieldSchema(tags: tags)
        self.profileID = profileID
        self.setKey = setKey
        self.tags = tags
        self.universalLabels = universalLabels
        self.itemOffsets = itemOffsets
        self.itemLengthEncodedWidths = itemLengthEncodedWidths
        self.baselineStreamOffsets = baselineStreamOffsets
        self.indexEntryValueLength = indexEntryValueLength
        self.indexEntryItemSize = indexEntryItemSize
        self.expectedIndexSID = expectedIndexSID
        self.expectedBodySID = expectedBodySID
        self.essenceStreamSpan = essenceStreamSpan
    }
}

enum MXFIndexFixtureDeclarationError: Error, Equatable, Sendable {
    case invalidSetKeyWidth
    case invalidTagSchema
    case incompleteFieldSchema
}

enum IndexMutations {
    static func fixtures(declarations: [MXFIndexFixtureDeclaration]) -> [any MXFFixtureMutation] {
        declarations.flatMap { declaration in
            IndexMutationKind.allCases.map { IndexMutation(kind: $0, declaration: declaration) }
        }
    }
}

private enum IndexMutationKind: String, CaseIterable, Sendable {
    case entryExceedsPayload = "count.indexEntryExceedsPayload.v1"
    case streamOffsetBeyondEssence = "index.streamOffsetBeyondEssence.v1"
    case streamOffsetsBackward = "index.streamOffsetsBackward.v1"
    case streamOffsetsDuplicate = "index.streamOffsetsDuplicate.v1"
    case sidMismatch = "index.sidMismatch.v1"
    case bodySIDMismatch = "index.bodySIDMismatch.v1"
    case editRateZeroDenominator = "index.editRateZeroDenominator.v1"
}

private enum IndexMutationError: Error, Equatable, Sendable {
    case targetUnavailable(String)
    case shortRead(UInt64)
    case preconditionChanged(String)
    case postconditionFailed(String)
}

private struct IndexTarget: Sendable {
    let setSpan: ByteSpan
    let fieldSpan: ByteSpan
    let original: UInt64
    let replacement: UInt64
    let field: String
    let classification: String
    let entryIndex: UInt64?
}

private struct IndexMutation: MXFFixtureMutation {
    let kind: IndexMutationKind
    let declaration: MXFIndexFixtureDeclaration

    var definition: MXFFixtureDefinition {
        MXFFixtureDefinition(
            id: kind.rawValue, title: kind.rawValue,
            rationale: "Exercises one bounded, field-aware index-table semantic defect.",
            corpusClass: .parserConformance, lifecycle: .draft, mutationSchemaVersion: 1,
            requiredSourceCharacteristics: [
                "declared synthetic index profile \(declaration.profileID)",
                "exact 16-byte set key, explicit primer tags, item offsets, and valid baseline relationships"
            ],
            targetSelectionRule: "first complete declared index set whose six tags occur at their declared offsets and whose baseline passes bounded index inspection",
            parameters: definitionParameters,
            seed: nil, expectedStructuralCondition: expectedCategory,
            defaultExpectedResult: .init(outcome: .rejected, category: expectedCategory, consumerCode: nil),
            recommendedLimits: Self.limits
        )
    }

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        guard let target = target(in: source) else {
            return .notApplicable(reason: "source lacks isolated declared index preconditions for \(declaration.profileID)")
        }
        return .applicable(targetOffset: target.fieldSpan.lowerBound,
                           targetClassification: target.classification)
    }

    func apply(to workingFile: URL, source: MXFInspectedFile, rng: inout SeededRNG) throws -> MXFMutationRecord {
        guard let target = target(in: source) else { throw IndexMutationError.targetUnavailable(kind.rawValue) }
        let baselineData = try Data(contentsOf: workingFile, options: .mappedIfSafe)
        guard case .indexTable = inspector.inspect(
            data: baselineData, setSpan: target.setSpan, schema: try schema, primerMap: try primerMap,
            limits: Self.inspectionLimits, relationships: relationships
        ) else { throw IndexMutationError.preconditionChanged("declared index baseline") }
        let original = try read(workingFile, target.fieldSpan)
        let actual = try decode(original)
        guard actual == target.original else { throw IndexMutationError.preconditionChanged(target.field) }
        let replacement = encode(target.replacement, width: target.fieldSpan.length)
        let edit = try MXFMutationRecorder().recordEdit(
            offset: target.fieldSpan.lowerBound, original: original, replacement: replacement, field: target.field
        )
        try MXFEditApplicator().apply(edits: [edit], truncation: nil, to: workingFile)
        return MXFMutationRecord(
            targetOffset: MXFDecimalUInt64(target.fieldSpan.lowerBound),
            targetClassification: target.classification, edits: [edit], truncation: nil,
            semanticValues: [try MXFSemanticValue(field: target.field, kind: .unsigned,
                                                   original: String(target.original),
                                                   replacement: String(target.replacement))]
        )
    }

    func postconditions(for source: MXFInspectedFile) -> [MXFPostcondition] {
        guard let target = target(in: source) else { return [] }
        return [{ context in
            let data = try Data(contentsOf: context.outputURL, options: .mappedIfSafe)
            let result = self.inspector.inspect(
                data: data, setSpan: target.setSpan, schema: try self.schema,
                primerMap: try self.primerMap, limits: self.postconditionLimits,
                relationships: self.relationships
            )
            guard self.matches(result, target: target) else {
                throw IndexMutationError.postconditionFailed("\(self.kind.rawValue): \(result)")
            }
        }]
    }

    private func target(in source: MXFInspectedFile) -> IndexTarget? {
        for element in source.elements where element.key == declaration.setKey {
            guard let setSpan = element.valueSpan else { continue }
            let chosen: (ByteSpan, UInt64, UInt64, String, UInt64?)?
            switch kind {
            case .entryExceedsPayload:
                guard !declaration.baselineStreamOffsets.isEmpty,
                      let span = span(.indexEntryArray, fieldOffset: 0, width: 4, setSpan: setSpan) else { continue }
                guard declaration.indexEntryValueLength >= 8, declaration.indexEntryItemSize > 0 else { continue }
                let replacement = (declaration.indexEntryValueLength - 8) / UInt64(declaration.indexEntryItemSize) + 1
                chosen = (span, UInt64(declaration.baselineStreamOffsets.count), replacement,
                          "index.indexEntryArray.count", nil)
            case .streamOffsetBeyondEssence:
                guard let first = declaration.baselineStreamOffsets.first,
                      declaration.essenceStreamSpan.length != first,
                      let span = entryOffsetSpan(index: 0, setSpan: setSpan) else { continue }
                chosen = (span, first, declaration.essenceStreamSpan.length, "index.indexEntryArray.streamOffset", 0)
            case .streamOffsetsBackward:
                guard declaration.baselineStreamOffsets.count >= 2,
                      declaration.baselineStreamOffsets[0] > 0,
                      let span = entryOffsetSpan(index: 1, setSpan: setSpan) else { continue }
                chosen = (span, declaration.baselineStreamOffsets[1], declaration.baselineStreamOffsets[0] - 1,
                          "index.indexEntryArray.streamOffset", 1)
            case .streamOffsetsDuplicate:
                guard declaration.baselineStreamOffsets.count >= 2,
                      let span = entryOffsetSpan(index: 1, setSpan: setSpan) else { continue }
                chosen = (span, declaration.baselineStreamOffsets[1], declaration.baselineStreamOffsets[0],
                          "index.indexEntryArray.streamOffset", 1)
            case .sidMismatch:
                guard declaration.expectedIndexSID < UInt32.max,
                      let span = span(.indexSID, fieldOffset: 0, width: 4, setSpan: setSpan) else { continue }
                chosen = (span, UInt64(declaration.expectedIndexSID), UInt64(declaration.expectedIndexSID + 1), "index.indexSID", nil)
            case .bodySIDMismatch:
                guard declaration.expectedBodySID < UInt32.max,
                      let span = span(.bodySID, fieldOffset: 0, width: 4, setSpan: setSpan) else { continue }
                chosen = (span, UInt64(declaration.expectedBodySID), UInt64(declaration.expectedBodySID + 1), "index.bodySID", nil)
            case .editRateZeroDenominator:
                guard let span = span(.indexEditRate, fieldOffset: 4, width: 4, setSpan: setSpan) else { continue }
                chosen = (span, 1, 0, "index.indexEditRate.denominator", nil)
            }
            guard let chosen, chosen.1 != chosen.2 else { continue }
            let tag = tagForKind
            let relative = chosen.0.lowerBound - setSpan.lowerBound
            let classification = String(format: "indexSet:%@:tag.0x%04x:%@:offset.%llu",
                                        declaration.profileID, tag, chosen.3, relative)
            return .init(setSpan: setSpan, fieldSpan: chosen.0, original: chosen.1,
                         replacement: chosen.2, field: chosen.3,
                         classification: classification, entryIndex: chosen.4)
        }
        return nil
    }

    private func span(_ field: MXFIndexTableField, fieldOffset: UInt64, width: UInt64,
                      setSpan: ByteSpan) -> ByteSpan? {
        guard let item = declaration.itemOffsets[field], let ber = declaration.itemLengthEncodedWidths[field],
              let header = try? CheckedBinaryArithmetic.add(2, ber),
              let start = try? CheckedBinaryArithmetic.add(setSpan.lowerBound, item),
              let value = try? CheckedBinaryArithmetic.add(start, header),
              let offset = try? CheckedBinaryArithmetic.add(value, fieldOffset),
              let result = try? ByteSpan(offset: offset, length: width), result.upperBound <= setSpan.upperBound else { return nil }
        return result
    }

    private func entryOffsetSpan(index: Int, setSpan: ByteSpan) -> ByteSpan? {
        // The declared synthetic entry layout places StreamOffset at +3 within each entry.
        span(.indexEntryArray, fieldOffset: 8 + UInt64(index) * UInt64(declaration.indexEntryItemSize) + 3,
             width: 8, setSpan: setSpan)
    }

    private func matches(_ result: MXFIndexTableInspectionResult, target: IndexTarget) -> Bool {
        switch (kind, result) {
        case (.entryExceedsPayload, .invalid(.invalidBatch(field: .indexEntryArray, error: .payloadExceedsEnclosingSpan(let header, _, _, _)))):
            return header.count.span == target.fieldSpan && header.count.value == target.replacement
        case (.streamOffsetBeyondEssence, .invalid(.streamOffsetOutsideEssence(let index, let value, let span, let essence))):
            return index == target.entryIndex && value == target.replacement && span == target.fieldSpan && essence == declaration.essenceStreamSpan
        case (.streamOffsetsBackward, .invalid(.nonIncreasingStreamOffset(let index, let previous, let current, let span))):
            return index == target.entryIndex && current == target.replacement && current < previous && span == target.fieldSpan
        case (.streamOffsetsDuplicate, .invalid(.nonIncreasingStreamOffset(let index, let previous, let current, let span))):
            return index == target.entryIndex && current == target.replacement && current == previous && span == target.fieldSpan
        case (.sidMismatch, .invalid(.indexSIDMismatch(let actual, let expected, let span))):
            return UInt64(actual) == target.replacement && expected == declaration.expectedIndexSID && span == target.fieldSpan
        case (.bodySIDMismatch, .invalid(.bodySIDMismatch(let actual, let expected, let span))):
            return UInt64(actual) == target.replacement && expected == declaration.expectedBodySID && span == target.fieldSpan
        case (.editRateZeroDenominator, .invalid(.zeroEditRateDenominator(let span))):
            return span == target.fieldSpan
        default: return false
        }
    }

    private var inspector: MXFIndexTableInspector { MXFIndexTableInspector() }
    private var schema: MXFIndexTableFieldSchema { get throws { try .init(tags: declaration.tags) } }
    private var primerMap: MXFPrimerMap { get throws { try .init(mappings: declaration.universalLabels) } }
    private var relationships: MXFIndexTableRelationships {
        .init(essenceStreamSpan: declaration.essenceStreamSpan,
              expectedIndexSID: declaration.expectedIndexSID, expectedBodySID: declaration.expectedBodySID)
    }
    private var tagForKind: UInt16 {
        let field: MXFIndexTableField
        switch kind {
        case .entryExceedsPayload, .streamOffsetBeyondEssence, .streamOffsetsBackward, .streamOffsetsDuplicate: field = .indexEntryArray
        case .sidMismatch: field = .indexSID
        case .bodySIDMismatch: field = .bodySID
        case .editRateZeroDenominator: field = .indexEditRate
        }
        return declaration.tags.first(where: { $0.value == field })!.key
    }

    private var definitionParameters: [String: String] {
        var result = ["sourceProfile": declaration.profileID,
                      "setKey": declaration.setKey.map { String(format: "%02x", $0) }.joined()]
        for (field, offset) in declaration.itemOffsets {
            let tag = declaration.tags.first(where: { $0.value == field })!.key
            result[field.rawValue] = String(format: "tag=0x%04x,itemOffset=%llu", tag, offset)
        }
        return result
    }

    private var expectedCategory: String {
        switch kind {
        case .entryExceedsPayload: return "invalidCount"
        case .streamOffsetBeyondEssence, .streamOffsetsBackward, .streamOffsetsDuplicate: return "invalidOffset"
        case .sidMismatch, .bodySIDMismatch: return "referenceMismatch"
        case .editRateZeroDenominator: return "invalidRate"
        }
    }
    private var postconditionLimits: MXFInspectionLimits { .init(maximumElementCount: 32, maximumAllocationBytes: 4_096) }
    private static let inspectionLimits = MXFInspectionLimits(maximumElementCount: 32, maximumAllocationBytes: 4_096)
    private static let limits = MXFReaderLimits(
        maxInputBytes: .init(64 * 1_024 * 1_024), maxKLVElements: .init(100_000),
        maxBERValueLength: .init(32 * 1_024 * 1_024), maxAllocationBytes: .init(4_096),
        maxLocalSetItems: .init(32), maxPartitionHops: .init(128), maxVisitedOffsets: .init(128)
    )

    private func read(_ url: URL, _ span: ByteSpan) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        try handle.seek(toOffset: span.lowerBound)
        let count = try CheckedBinaryArithmetic.int(exactly: span.length)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw IndexMutationError.shortRead(span.lowerBound) }
        return data
    }
    private func decode(_ data: Data) throws -> UInt64 {
        data.count == 8 ? try data.checkedUInt64BE(at: 0) : UInt64(try data.checkedUInt32BE(at: 0))
    }
    private func encode(_ value: UInt64, width: UInt64) -> Data {
        let count = Int(width)
        return Data((0..<count).map { UInt8(value >> UInt64((count - 1 - $0) * 8)) })
    }
}
