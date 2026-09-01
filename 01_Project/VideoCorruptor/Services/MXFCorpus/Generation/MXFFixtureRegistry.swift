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

struct MXFFixtureRegistry: Sendable {
    private let fixtures: [any MXFFixtureMutation]

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
