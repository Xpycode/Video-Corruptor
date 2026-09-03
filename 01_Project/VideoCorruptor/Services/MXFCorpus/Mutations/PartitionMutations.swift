import Foundation

enum PartitionMutations {
    static let fixtures: [any MXFFixtureMutation] = PartitionMutationKind.allCases.map(PartitionMutation.init)
}

private enum PartitionMutationKind: String, CaseIterable, Sendable {
    case footerAtEOF = "partition.footerAtEOF.v1"
    case footerBeyondEOF = "partition.footerBeyondEOF.v1"
    case footerInsideValue = "partition.footerInsideValue.v1"
    case footerWrongKey = "partition.footerWrongKey.v1"
    case thisOffsetMismatch = "partition.thisOffsetMismatch.v1"
    case previousSelfCycle = "partition.previousSelfCycle.v1"
    case previousTwoNodeCycle = "partition.previousTwoNodeCycle.v1"
}

private enum PartitionMutationError: Error, Equatable, Sendable {
    case targetUnavailable(String)
    case replacementAlreadyPresent(String)
    case postconditionFailed(String)
    case shortRead(offset: UInt64)
}

private struct PartitionTarget: Sendable {
    let primary: MXFInspectedElement
    let secondary: MXFInspectedElement?
    let replacement: UInt64
    let classification: String
}

private struct PartitionMutation: MXFFixtureMutation {
    let kind: PartitionMutationKind

    var definition: MXFFixtureDefinition {
        MXFFixtureDefinition(
            id: kind.rawValue,
            title: title,
            rationale: rationale,
            corpusClass: .parserConformance,
            lifecycle: .draft,
            mutationSchemaVersion: 1,
            requiredSourceCharacteristics: requiredCharacteristics,
            targetSelectionRule: selectionRule,
            parameters: ["sourceProfile": "recorded-by-generator"],
            seed: nil,
            expectedStructuralCondition: structuralCondition,
            defaultExpectedResult: MXFExpectedResult(
                outcome: .rejected,
                category: expectedCategory,
                consumerCode: nil
            ),
            recommendedLimits: Self.limits
        )
    }

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        guard let target = target(in: source) else {
            return .notApplicable(reason: notApplicableReason)
        }
        guard let span = fieldSpan(for: target.primary) else {
            return .notApplicable(reason: notApplicableReason)
        }
        return .applicable(
            targetOffset: span.lowerBound,
            targetClassification: target.classification
        )
    }

    func apply(
        to workingFile: URL,
        source: MXFInspectedFile,
        rng: inout SeededRNG
    ) throws -> MXFMutationRecord {
        guard let target = target(in: source) else {
            throw PartitionMutationError.targetUnavailable(kind.rawValue)
        }
        guard let primarySpan = fieldSpan(for: target.primary) else {
            throw PartitionMutationError.targetUnavailable(kind.rawValue)
        }
        let edits: [MXFByteEdit]
        var semantics: [MXFSemanticValue] = []
        switch kind {
        case .previousTwoNodeCycle:
            guard let secondary = target.secondary else {
                throw PartitionMutationError.targetUnavailable(kind.rawValue)
            }
            let pairs = [(target.primary, secondary.keySpan.lowerBound),
                         (secondary, target.primary.keySpan.lowerBound)]
            edits = try pairs.compactMap { element, replacement in
                guard let span = previousSpan(element) else {
                    throw PartitionMutationError.targetUnavailable(kind.rawValue)
                }
                let original = try readUInt64(fileAt: workingFile, span: span)
                guard original != replacement else { return nil }
                semantics.append(try semantic(field: "partition.previousPartition", original, replacement))
                return try makeEdit(fileAt: workingFile, span: span, replacement: replacement,
                                    field: "partition.previousPartition")
            }
        default:
            let span = primarySpan
            let original = try readUInt64(fileAt: workingFile, span: span)
            guard original != target.replacement else {
                throw PartitionMutationError.replacementAlreadyPresent(kind.rawValue)
            }
            edits = [try makeEdit(fileAt: workingFile, span: span, replacement: target.replacement,
                                  field: fieldName)]
            semantics = [try semantic(field: fieldName, original, target.replacement)]
        }
        guard !edits.isEmpty else {
            throw PartitionMutationError.replacementAlreadyPresent(kind.rawValue)
        }
        let sorted = try MXFMutationRecorder().validateAndSort(edits: edits)
        try MXFEditApplicator().apply(edits: sorted, truncation: nil, to: workingFile)
        return MXFMutationRecord(
            targetOffset: MXFDecimalUInt64(primarySpan.lowerBound),
            targetClassification: target.classification,
            edits: sorted,
            truncation: nil,
            semanticValues: semantics
        )
    }

    func postconditions(for source: MXFInspectedFile) -> [MXFPostcondition] {
        guard let target = target(in: source) else { return [] }
        return [{ context in
            let structural = try MXFStructuralInspector().inspect(fileAt: context.outputURL)
            guard structural.completedWalk else {
                throw PartitionMutationError.postconditionFailed("structural walk did not complete")
            }
            let start = target.primary.keySpan.lowerBound
            let following: MXFPartitionLinkKind = self.kind.isFooter ? .footer : .previous
            let graph = try MXFPartitionGraphInspector().inspect(
                fileAt: context.outputURL,
                structuralFile: structural,
                traversalStartOffset: start,
                following: following,
                limits: .init(maximumPartitionHops: 4, maximumVisitedOffsets: 4)
            )
            guard self.matches(graph: graph, target: target) else {
                throw PartitionMutationError.postconditionFailed("\(self.kind.rawValue): \(graph)")
            }
        }]
    }

    private func target(in source: MXFInspectedFile) -> PartitionTarget? {
        let partitions = source.elements
            .filter { MXFPartitionInspector().classify(key: $0.key) != nil && $0.valueSpan?.length ?? 0 >= 88 }
            .sorted { $0.keySpan.lowerBound < $1.keySpan.lowerBound }
        guard let first = partitions.first else { return nil }
        switch kind {
        case .footerAtEOF:
            return PartitionTarget(primary: first, secondary: nil, replacement: source.inputByteCount,
                                   classification: "partition.footerPartition:endOfFile")
        case .footerBeyondEOF:
            guard let replacement = try? CheckedBinaryArithmetic.add(source.inputByteCount, 1) else { return nil }
            return PartitionTarget(primary: first, secondary: nil, replacement: replacement,
                                   classification: "partition.footerPartition:beyondEndOfFile")
        case .footerInsideValue:
            guard let element = source.elements.first(where: {
                guard let value = $0.valueSpan, value.length > 0 else { return false }
                return value.lowerBound != 0
            }), let value = element.valueSpan else { return nil }
            return PartitionTarget(primary: first, secondary: nil, replacement: value.lowerBound,
                                   classification: "partition.footerPartition:insideValue")
        case .footerWrongKey:
            guard let element = source.elements.first(where: {
                $0.keySpan.lowerBound != 0 && MXFPartitionInspector().classify(key: $0.key) == nil
            }) else { return nil }
            return PartitionTarget(primary: first, secondary: nil, replacement: element.keySpan.lowerBound,
                                   classification: "partition.footerPartition:wrongKey")
        case .thisOffsetMismatch:
            guard let replacement = try? CheckedBinaryArithmetic.add(first.keySpan.lowerBound, 1) else { return nil }
            return PartitionTarget(primary: first, secondary: nil, replacement: replacement,
                                   classification: "partition.thisPartition:mismatch")
        case .previousSelfCycle:
            let selected = partitions.last ?? first
            guard selected.keySpan.lowerBound != 0 else { return nil }
            return PartitionTarget(primary: selected, secondary: nil, replacement: selected.keySpan.lowerBound,
                                   classification: "partition.previousPartition:selfCycle")
        case .previousTwoNodeCycle:
            // Zero is the MXF sentinel for "no previous partition", so a header at physical
            // offset zero cannot participate as a resolvable previous-link cycle node.
            let cycleNodes = partitions.filter { $0.keySpan.lowerBound != 0 }
            guard cycleNodes.count >= 2 else { return nil }
            return PartitionTarget(primary: cycleNodes[0], secondary: cycleNodes[1], replacement: 0,
                                   classification: "partition.previousPartition:twoNodeCycle")
        }
    }

    private func matches(graph: MXFPartitionGraph, target: PartitionTarget) -> Bool {
        let start = target.primary.keySpan.lowerBound
        switch kind {
        case .footerAtEOF:
            return graph.nodesByPhysicalOffset[start]?.footer.resolution == .endOfFile
                && graph.traversal.hopCount == 1 && graph.traversal.terminatedAt == .endOfFile
        case .footerBeyondEOF:
            return graph.nodesByPhysicalOffset[start]?.footer.resolution == .beyondEndOfFile
                && graph.traversal.hopCount == 1 && graph.traversal.terminatedAt == .beyondEndOfFile
        case .footerInsideValue:
            guard case .insideElement = graph.nodesByPhysicalOffset[start]?.footer.resolution else { return false }
            return graph.traversal.hopCount == 1
        case .footerWrongKey:
            guard case .nonPartitionElement = graph.nodesByPhysicalOffset[start]?.footer.resolution else { return false }
            return graph.traversal.hopCount == 1
        case .thisOffsetMismatch:
            guard let span = thisSpan(target.primary) else { return false }
            return graph.diagnostics.contains(.thisPartitionMismatch(
                physicalOffset: start, declaredOffset: target.replacement,
                fieldSpan: span
            )) && graph.traversal.hopCount == 0
        case .previousSelfCycle:
            return graph.traversal.hopCount == 1
                && graph.diagnostics.contains(.cycle(kind: .previous, offsets: [start, start]))
        case .previousTwoNodeCycle:
            guard let second = target.secondary?.keySpan.lowerBound else { return false }
            return graph.traversal.hopCount == 2
                && graph.diagnostics.contains(.cycle(kind: .previous, offsets: [start, second, start]))
        }
    }

    private var fieldName: String {
        kind == .thisOffsetMismatch ? "partition.thisPartition" :
            (kind.isFooter ? "partition.footerPartition" : "partition.previousPartition")
    }

    private func fieldSpan(for element: MXFInspectedElement) -> ByteSpan? {
        kind == .thisOffsetMismatch ? thisSpan(element) :
            (kind.isFooter ? footerSpan(element) : previousSpan(element))
    }

    private func thisSpan(_ element: MXFInspectedElement) -> ByteSpan? {
        fieldSpan(element, relativeOffset: 8)
    }

    private func previousSpan(_ element: MXFInspectedElement) -> ByteSpan? {
        fieldSpan(element, relativeOffset: 16)
    }

    private func footerSpan(_ element: MXFInspectedElement) -> ByteSpan? {
        fieldSpan(element, relativeOffset: 24)
    }

    private func fieldSpan(_ element: MXFInspectedElement, relativeOffset: UInt64) -> ByteSpan? {
        guard let valueSpan = element.valueSpan,
              let offset = try? CheckedBinaryArithmetic.add(valueSpan.lowerBound, relativeOffset)
        else { return nil }
        return try? ByteSpan(offset: offset, length: 8)
    }

    private func readUInt64(fileAt url: URL, span: ByteSpan) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: span.lowerBound)
        let data = try handle.read(upToCount: 8) ?? Data()
        guard data.count == 8 else { throw PartitionMutationError.shortRead(offset: span.lowerBound) }
        return try data.checkedUInt64BE(at: 0)
    }

    private func makeEdit(fileAt url: URL, span: ByteSpan, replacement: UInt64, field: String) throws -> MXFByteEdit {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: span.lowerBound)
        let original = try handle.read(upToCount: 8) ?? Data()
        guard original.count == 8 else { throw PartitionMutationError.shortRead(offset: span.lowerBound) }
        var bytes = Data(repeating: 0, count: 8)
        try bytes.checkedWriteUInt64BE(replacement, at: 0)
        return try MXFMutationRecorder().recordEdit(offset: span.lowerBound, original: original,
                                                    replacement: bytes, field: field)
    }

    private func semantic(field: String, _ original: UInt64, _ replacement: UInt64) throws -> MXFSemanticValue {
        try MXFSemanticValue(field: field, kind: .unsigned,
                             original: String(original), replacement: String(replacement))
    }

    private static let limits = MXFReaderLimits(
        maxInputBytes: MXFDecimalUInt64(64 * 1_024 * 1_024),
        maxKLVElements: MXFDecimalUInt64(100_000),
        maxBERValueLength: MXFDecimalUInt64(32 * 1_024 * 1_024),
        maxAllocationBytes: MXFDecimalUInt64(1 * 1_024 * 1_024),
        maxLocalSetItems: MXFDecimalUInt64(10_000),
        maxPartitionHops: MXFDecimalUInt64(128),
        maxVisitedOffsets: MXFDecimalUInt64(128)
    )

    private var title: String { kind.rawValue }
    private var rationale: String { "Exercises bounded validation of an MXF partition graph field." }
    private var requiredCharacteristics: [String] {
        kind == .previousTwoNodeCycle ? ["At least two complete partition packs"] : ["At least one complete partition pack"]
    }
    private var selectionRule: String { "Lowest physical partition offsets satisfying the case, with element ties sorted by physical offset." }
    private var structuralCondition: String { kind.rawValue + " is proven by bounded partition graph reinspection." }
    private var expectedCategory: String { kind == .previousSelfCycle || kind == .previousTwoNodeCycle ? "partitionCycle" : (kind == .footerInsideValue || kind == .footerWrongKey ? "invalidPartition" : "invalidOffset") }
    private var notApplicableReason: String { "Source graph/element shape cannot isolate \(kind.rawValue)." }
}

private extension PartitionMutationKind {
    var isFooter: Bool {
        switch self {
        case .footerAtEOF, .footerBeyondEOF, .footerInsideValue, .footerWrongKey: true
        default: false
        }
    }
}
