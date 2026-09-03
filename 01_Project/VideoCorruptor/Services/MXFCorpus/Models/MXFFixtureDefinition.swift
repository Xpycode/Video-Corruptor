import Foundation

enum MXFModelError: Error, Equatable, Sendable {
    case invalidUnsignedDecimal(String)
    case invalidSignedDecimal(String)
    case invalidLowercaseHex(String)
    case invalidRelativePath(String)
    case invalidSHA256(String)
    case invalidTruncation(originalSize: UInt64, retainedSize: UInt64)
    case publicationEligibilityExceedsSourceRights
}

struct MXFDecimalUInt64: Codable, Hashable, Sendable {
    let value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    init(decimalString: String) throws {
        guard Self.isCanonical(decimalString), let value = UInt64(decimalString) else {
            throw MXFModelError.invalidUnsignedDecimal(decimalString)
        }
        self.value = value
    }

    init(from decoder: Decoder) throws {
        try self.init(decimalString: decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(value))
    }

    private static func isCanonical(_ string: String) -> Bool {
        guard !string.isEmpty else { return false }
        if string == "0" { return true }
        guard string.first.map({ $0 >= "1" && $0 <= "9" }) == true else { return false }
        return string.dropFirst().allSatisfy { $0 >= "0" && $0 <= "9" }
    }
}

struct MXFLowercaseHex: Codable, Hashable, Sendable {
    let value: String

    init(_ value: String) throws {
        guard !value.isEmpty,
              value.count.isMultiple(of: 2),
              value.allSatisfy({ ($0 >= "0" && $0 <= "9") || ("a"..."f").contains($0) }) else {
            throw MXFModelError.invalidLowercaseHex(value)
        }
        self.value = value
    }

    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct MXFRelativePath: Codable, Hashable, Sendable {
    let value: String

    init(_ value: String) throws {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("\\"),
              !value.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw MXFModelError.invalidRelativePath(value)
        }
        self.value = value
    }

    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

enum MXFCorpusClass: String, Codable, Sendable {
    case parserConformance
    case decoderIntegration
    case fuzzStress
    case cancellation
}

enum MXFFixtureLifecycle: String, Codable, Sendable {
    /// Schema-v1 compatibility for definitions created before release stages were explicit.
    case draft
    case generated
    case structurallyVerified
    case consumerMapped
    case approved
    case deprecated
}

enum MXFFixtureLifecycleTransitionError: Error, Equatable, Sendable {
    case outOfOrder(from: MXFFixtureLifecycle, to: MXFFixtureLifecycle)
    case missingConsumerCode(stage: MXFFixtureLifecycle)
}

enum MXFFixtureLifecycleTransition {
    /// Validates one release transition. `draft` is retained as a schema-v1 authoring state and
    /// may only enter the ordered release lifecycle at `generated`.
    static func validate(
        from: MXFFixtureLifecycle,
        to: MXFFixtureLifecycle,
        consumerCode: String?
    ) throws {
        let allowed: Bool = switch (from, to) {
        case (.draft, .generated), (.generated, .structurallyVerified),
             (.structurallyVerified, .consumerMapped), (.consumerMapped, .approved):
            true
        default:
            false
        }
        guard allowed else {
            throw MXFFixtureLifecycleTransitionError.outOfOrder(from: from, to: to)
        }
        if to == .consumerMapped || to == .approved {
            guard let consumerCode,
                  !consumerCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MXFFixtureLifecycleTransitionError.missingConsumerCode(stage: to)
            }
        }
    }
}

enum MXFExpectedOutcome: String, Codable, Sendable {
    case accepted
    case acceptedWithWarning
    case rejected
}

enum MXFFixtureApplicability: Equatable, Sendable {
    case applicable(targetOffset: UInt64, targetClassification: String)
    case notApplicable(reason: String)
}

struct MXFExpectedResult: Codable, Equatable, Sendable {
    let outcome: MXFExpectedOutcome
    let category: String
    let consumerCode: String?
}

struct MXFReaderLimits: Codable, Equatable, Sendable {
    let maxInputBytes: MXFDecimalUInt64
    let maxKLVElements: MXFDecimalUInt64
    let maxBERValueLength: MXFDecimalUInt64
    let maxAllocationBytes: MXFDecimalUInt64
    let maxLocalSetItems: MXFDecimalUInt64
    let maxPartitionHops: MXFDecimalUInt64
    let maxVisitedOffsets: MXFDecimalUInt64
}

struct MXFFixtureDefinition: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let rationale: String
    let corpusClass: MXFCorpusClass
    let lifecycle: MXFFixtureLifecycle
    let mutationSchemaVersion: Int
    let requiredSourceCharacteristics: [String]
    let targetSelectionRule: String
    let parameters: [String: String]
    let seed: MXFDecimalUInt64?
    let expectedStructuralCondition: String
    let defaultExpectedResult: MXFExpectedResult
    let recommendedLimits: MXFReaderLimits

    enum CodingKeys: String, CodingKey {
        case id, title, rationale, lifecycle, mutationSchemaVersion
        case requiredSourceCharacteristics, targetSelectionRule, parameters, seed
        case expectedStructuralCondition, defaultExpectedResult, recommendedLimits
        case corpusClass = "class"
    }
}
