import Foundation

enum MXFDeclaredProfile: String, Sendable {
    case op1a = "OP1a"
    case opAtom = "OP-Atom"
}

struct MXFMissingStructureSourceDeclaration: Sendable {
    let profile: MXFDeclaredProfile
    let missingFooter: MXFExpectedResult
    let missingRIP: MXFExpectedResult

    static let op1a = MXFMissingStructureSourceDeclaration(
        profile: .op1a,
        missingFooter: .init(outcome: .rejected, category: "missingFooter", consumerCode: nil),
        missingRIP: .init(outcome: .acceptedWithWarning, category: "missingRIP", consumerCode: nil)
    )

    static let opAtom = MXFMissingStructureSourceDeclaration(
        profile: .opAtom,
        missingFooter: .init(outcome: .acceptedWithWarning, category: "missingFooterFallback", consumerCode: nil),
        missingRIP: .init(outcome: .acceptedWithWarning, category: "missingRIP", consumerCode: nil)
    )
}

enum MXFMissingStructureKind: String, CaseIterable, Sendable {
    case headerPartition
    case footerPartition
    case rip
}

enum MXFMissingStructureMutationError: Error, Equatable, Sendable {
    case preconditionChanged(String)
    case postconditionFailed(String)
}

struct MXFMissingStructureMutation: MXFFixtureMutation, Sendable {
    let kind: MXFMissingStructureKind
    let sourceDeclaration: MXFMissingStructureSourceDeclaration?

    var definition: MXFFixtureDefinition {
        MXFFixtureDefinition(
            id: "mxf.missing.\(kind.rawValue).v1",
            title: title,
            rationale: "Isolates one declared missing MXF structure without assuming a profile-independent policy.",
            corpusClass: .parserConformance,
            lifecycle: .draft,
            mutationSchemaVersion: 1,
            requiredSourceCharacteristics: [requiredCharacteristic],
            targetSelectionRule: selectionRule,
            parameters: ["profile": sourceDeclaration?.profile.rawValue ?? "undeclared"],
            seed: nil,
            expectedStructuralCondition: structuralCondition,
            defaultExpectedResult: expectedResult,
            recommendedLimits: Self.readerLimits
        )
    }

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        guard sourceDeclaration != nil else {
            return .notApplicable(reason: "A typed OP1a or OP-Atom source/profile declaration is required")
        }
        guard let target = target(in: source) else {
            return .notApplicable(reason: "Source lacks a verified \(kind.rawValue) target")
        }
        return .applicable(targetOffset: target.offset, targetClassification: target.classification)
    }

    func apply(to workingFile: URL, source: MXFInspectedFile, rng: inout SeededRNG) throws -> MXFMutationRecord {
        _ = rng
        guard sourceDeclaration != nil, let target = target(in: source) else {
            throw MXFMissingStructureMutationError.preconditionChanged(kind.rawValue)
        }
        var edits: [MXFByteEdit] = []
        var truncation: MXFTruncationRecord?
        switch kind {
        case .headerPartition:
            let original = Data([target.key[13]])
            let edit = try MXFMutationRecorder().recordEdit(
                offset: target.offset + 13,
                original: original,
                replacement: Data([0x05]),
                field: "headerPartitionKeyKind"
            )
            edits = [edit]
        case .footerPartition, .rip:
            truncation = try MXFTruncationRecord(
                originalSize: source.inputByteCount,
                retainedSize: target.offset,
                containingElement: target.classification,
                boundary: "immediately before verified \(kind.rawValue) key"
            )
        }
        try MXFEditApplicator().apply(edits: edits, truncation: truncation, to: workingFile)
        return MXFMutationRecord(
            targetOffset: MXFDecimalUInt64(target.offset),
            targetClassification: target.classification,
            edits: edits,
            truncation: truncation,
            semanticValues: []
        )
    }

    func postconditions(for source: MXFInspectedFile) -> [MXFPostcondition] {
        guard let target = target(in: source) else { return [] }
        return [{ context in
            let output = try MXFStructuralInspector().inspect(fileAt: context.outputURL)
            switch self.kind {
            case .headerPartition:
                let headerExists = output.elements.contains {
                    MXFPartitionInspector().classify(key: $0.key)?.kind == .header
                }
                guard !headerExists else {
                    throw MXFMissingStructureMutationError.postconditionFailed("header partition remains")
                }
            case .footerPartition, .rip:
                let handle = try FileHandle(forReadingFrom: context.outputURL)
                defer { try? handle.close() }
                guard try handle.seekToEnd() == target.offset else {
                    throw MXFMissingStructureMutationError.postconditionFailed("incorrect structural boundary")
                }
            }
        }]
    }

    private struct Target: Sendable {
        let offset: UInt64
        let classification: String
        let key: Data
    }

    private func target(in source: MXFInspectedFile) -> Target? {
        switch kind {
        case .headerPartition:
            guard let element = source.elements.first(where: {
                MXFPartitionInspector().classify(key: $0.key)?.kind == .header
            }) else { return nil }
            return .init(offset: element.keySpan.lowerBound, classification: "header partition key", key: element.key)
        case .footerPartition:
            guard let element = source.elements.first(where: {
                MXFPartitionInspector().classify(key: $0.key)?.kind == .footer
            }), element.keySpan.lowerBound > 0 else { return nil }
            return .init(offset: element.keySpan.lowerBound, classification: "footer partition and trailing bytes", key: element.key)
        case .rip:
            guard let element = source.elements.first(where: { Self.isRandomIndexPackKey($0.key) }),
                  element.keySpan.lowerBound > 0 else { return nil }
            return .init(offset: element.keySpan.lowerBound, classification: "random index pack and trailing bytes", key: element.key)
        }
    }

    private static func isRandomIndexPackKey(_ key: Data) -> Bool {
        key == Data([0x06, 0x0e, 0x2b, 0x34, 0x02, 0x05, 0x01, 0x01,
                     0x0d, 0x01, 0x02, 0x01, 0x01, 0x11, 0x01, 0x00])
    }

    private var expectedResult: MXFExpectedResult {
        guard let declaration = sourceDeclaration else {
            return .init(outcome: .rejected, category: "profileDeclarationRequired", consumerCode: nil)
        }
        switch kind {
        case .headerPartition:
            return .init(outcome: .rejected, category: "missingHeaderPartition", consumerCode: nil)
        case .footerPartition: return declaration.missingFooter
        case .rip: return declaration.missingRIP
        }
    }

    private var title: String { "Missing \(kind.rawValue)" }
    private var requiredCharacteristic: String {
        "Declared \(sourceDeclaration?.profile.rawValue ?? "OP1a or OP-Atom") source with a verified \(kind.rawValue)"
    }
    private var selectionRule: String { "Lowest-offset verified \(kind.rawValue) key" }
    private var structuralCondition: String {
        kind == .headerPartition
            ? "Exactly the selected header partition key-kind byte is changed; no header partition key remains."
            : "Output is an exact source prefix ending immediately before the selected verified structure."
    }

    private static let readerLimits = MXFReaderLimits(
        maxInputBytes: .init(1 << 30), maxKLVElements: .init(1_000_000),
        maxBERValueLength: .init(1 << 30), maxAllocationBytes: .init(64 << 20),
        maxLocalSetItems: .init(100_000), maxPartitionHops: .init(10_000),
        maxVisitedOffsets: .init(100_000)
    )
}

enum MXFMissingStructureMutations {
    static let undeclared: [MXFMissingStructureMutation] = fixtures()

    static func fixtures(
        sourceDeclaration: MXFMissingStructureSourceDeclaration? = nil
    ) -> [MXFMissingStructureMutation] {
        MXFMissingStructureKind.allCases.map {
            MXFMissingStructureMutation(kind: $0, sourceDeclaration: sourceDeclaration)
        }
    }
}
