import Foundation

protocol MXFFixtureMutation: Sendable {
    var definition: MXFFixtureDefinition { get }

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability
    func apply(
        to workingFile: URL,
        source: MXFInspectedFile,
        rng: inout SeededRNG
    ) throws -> MXFMutationRecord
    func postconditions(for source: MXFInspectedFile) -> [MXFPostcondition]
}

extension MXFFixtureMutation {
    func postconditions(for source: MXFInspectedFile) -> [MXFPostcondition] { [] }
}

enum MXFFixtureRegistryError: Error, Equatable, Sendable {
    case duplicateFixtureID(String)
    case unknownFixtureIDs([String])
}

/// Source declarations are deliberately supplied by the caller. The production registry knows
/// the corpus contract, but does not embed offsets or depend on the test-only synthetic builder.
struct MXFFixtureRegistryDeclarations: Sendable {
    let requiredBERElements: [MXFRequiredElementDeclaration]
    let missingStructures: MXFMissingStructureSourceDeclaration?
    let counts: [MXFCountFixtureDeclaration]
    let indexes: [MXFIndexFixtureDeclaration]

    init(
        requiredBERElements: [MXFRequiredElementDeclaration] = [],
        missingStructures: MXFMissingStructureSourceDeclaration? = nil,
        counts: [MXFCountFixtureDeclaration] = [],
        indexes: [MXFIndexFixtureDeclaration] = []
    ) {
        self.requiredBERElements = requiredBERElements
        self.missingStructures = missingStructures
        self.counts = counts
        self.indexes = indexes
    }
}

struct MXFFixtureRegistry: Sendable {
    private let fixtures: [any MXFFixtureMutation]

    /// The complete approved specification contract. Tests compare this exact set so adding or
    /// removing a mutation implementation cannot silently change corpus coverage.
    static let requiredFixtureIDs: Set<String> = [
        "ber.indefiniteForm.v1", "ber.lengthOfLengthTooLarge.v1", "ber.headerTruncated.v1",
        "ber.valueBeyondEOF.v1", "ber.lengthAdditionOverflow.v1", "ber.nonMinimalLongForm.v1",
        "ber.zeroRequiredValue.v1", "ber.shorterThanPayload.v1",
        "partition.footerMissing.v1", "partition.footerAtEOF.v1", "partition.footerBeyondEOF.v1",
        "partition.footerInsideValue.v1", "partition.footerWrongKey.v1",
        "partition.previousSelfCycle.v1", "partition.previousTwoNodeCycle.v1",
        "partition.thisOffsetMismatch.v1",
        "count.localSetItemExceedsValue.v1", "count.batchExceedsPayload.v1",
        "count.batchItemSizeZero.v1", "count.batchMultiplicationOverflow.v1",
        "count.indexEntryExceedsPayload.v1", "count.sliceDeltaExtreme.v1",
        "mxf.missing.headerPartition.v1", "mxf.missing.footerPartition.v1", "mxf.missing.rip.v1",
        "missing.index.v1", "missing.requiredMetadataSet.v1",
        "mxf.truncation.insideKey.v1", "mxf.truncation.immediatelyPostKey.v1",
        "mxf.truncation.insideLongBER.v1", "mxf.truncation.immediatelyPostLongBER.v1",
        "mxf.truncation.oneByteBeforeValueEnd.v1", "mxf.truncation.betweenCompleteKLVTriplets.v1",
        "mxf.truncation.insidePartitionFixedField.v1", "mxf.truncation.insideLocalSetItemHeader.v1",
        "mxf.truncation.insideLocalSetItemValue.v1", "mxf.truncation.insideIndexEntryArray.v1",
        "mxf.truncation.insideRIP.v1", "mxf.truncation.immediatelyBeforeRIP.v1",
        "index.streamOffsetBeyondEssence.v1", "index.streamOffsetsBackward.v1",
        "index.streamOffsetsDuplicate.v1", "index.sidMismatch.v1", "index.bodySIDMismatch.v1",
        "index.editRateZeroDenominator.v1"
    ]

    static func complete(
        declarations: MXFFixtureRegistryDeclarations = .init()
    ) throws -> MXFFixtureRegistry {
        var concrete: [any MXFFixtureMutation] = []
        concrete += BERMutations.fixtures(requiredElements: declarations.requiredBERElements)
        concrete += MXFTruncationMutations.all
        concrete += PartitionMutations.fixtures
        concrete += MXFMissingStructureMutations.fixtures(sourceDeclaration: declarations.missingStructures)
        concrete += CountMutations.fixtures(declarations: declarations.counts)
        concrete += IndexMutations.fixtures(declarations: declarations.indexes)

        let concreteIDs = Set(concrete.map(\.definition.id))
        let unavailable = requiredFixtureIDs.subtracting(concreteIDs).map {
            MXFUnavailableRequiredMutation(id: $0, reason: capabilityReason(for: $0))
        }
        return try MXFFixtureRegistry(fixtures: concrete + unavailable)
    }

    private static func capabilityReason(for id: String) -> String {
        switch id {
        case let value where value.hasPrefix("count."):
            return "Source lacks an explicit local-set/count declaration with verified tags and field offsets"
        case let value where value.hasPrefix("index."):
            return "Source lacks an explicit index-table declaration and verified essence relationships"
        case "missing.index.v1":
            return "Source lacks a verified index-table key whose absence is required by its declared profile"
        case "missing.requiredMetadataSet.v1":
            return "Source lacks a declared required metadata-set key and profile requirement"
        case let value where value.contains("LocalSet"):
            return "Source lacks a verified local-set item boundary"
        case "mxf.truncation.insideIndexEntryArray.v1":
            return "Source lacks a verified index-entry array boundary"
        case "mxf.truncation.insideRIP.v1", "mxf.truncation.immediatelyBeforeRIP.v1":
            return "Source lacks a verified Random Index Pack boundary"
        default:
            return "Source lacks the explicit structural declaration required by this fixture"
        }
    }

    init(fixtures: [any MXFFixtureMutation] = []) throws {
        var ids = Set<String>()
        for fixture in fixtures where !ids.insert(fixture.definition.id).inserted {
            throw MXFFixtureRegistryError.duplicateFixtureID(fixture.definition.id)
        }
        self.fixtures = fixtures.sorted { $0.definition.id < $1.definition.id }
    }

    func selected(ids: Set<String>?) throws -> [any MXFFixtureMutation] {
        guard let ids else { return fixtures }
        let known = Set(fixtures.map(\.definition.id))
        let unknown = ids.subtracting(known).sorted()
        guard unknown.isEmpty else { throw MXFFixtureRegistryError.unknownFixtureIDs(unknown) }
        return fixtures.filter { ids.contains($0.definition.id) }
    }
}

private struct MXFUnavailableRequiredMutation: MXFFixtureMutation {
    let id: String
    let reason: String

    var definition: MXFFixtureDefinition {
        MXFFixtureDefinition(
            id: id, title: id, rationale: "Required corpus case awaiting a source with verified structural capability.",
            corpusClass: .parserConformance, lifecycle: .draft, mutationSchemaVersion: 1,
            requiredSourceCharacteristics: [reason], targetSelectionRule: "No target without the declared capability",
            parameters: [:], seed: nil, expectedStructuralCondition: reason,
            defaultExpectedResult: .init(outcome: .rejected, category: "notApplicable", consumerCode: nil),
            recommendedLimits: .init(
                maxInputBytes: .init(1 << 30), maxKLVElements: .init(1_000_000),
                maxBERValueLength: .init(1 << 30), maxAllocationBytes: .init(64 << 20),
                maxLocalSetItems: .init(100_000), maxPartitionHops: .init(10_000),
                maxVisitedOffsets: .init(100_000)
            )
        )
    }

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability { .notApplicable(reason: reason) }
    func apply(to workingFile: URL, source: MXFInspectedFile, rng: inout SeededRNG) throws -> MXFMutationRecord {
        throw MXFUnavailableRequiredMutationError.notApplicable(id)
    }
}

private enum MXFUnavailableRequiredMutationError: Error { case notApplicable(String) }
