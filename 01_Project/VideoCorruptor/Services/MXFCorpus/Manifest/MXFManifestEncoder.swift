import Foundation

struct MXFManifestEncoder: Sendable {
    private let validator = MXFManifestValidator()

    func encode(_ manifest: MXFFixtureManifest) throws -> Data {
        try validator.validate(manifest)

        let fixtures = try manifest.fixtures
            .sorted { $0.id < $1.id }
            .map { fixture in
                let mutation = MXFMutationRecord(
                    targetOffset: fixture.mutation.targetOffset,
                    targetClassification: fixture.mutation.targetClassification,
                    edits: fixture.mutation.edits.sorted {
                        $0.offset.value < $1.offset.value
                    },
                    truncation: fixture.mutation.truncation,
                    semanticValues: fixture.mutation.semanticValues
                )
                return try MXFFixtureManifestEntry(
                    id: fixture.id,
                    corpusClass: fixture.corpusClass,
                    lifecycle: fixture.lifecycle,
                    mutationSchemaVersion: fixture.mutationSchemaVersion,
                    source: fixture.source,
                    output: fixture.output,
                    seed: fixture.seed,
                    mutation: mutation,
                    expected: fixture.expected,
                    limits: fixture.limits
                )
            }

        let canonical = MXFFixtureManifest(
            generator: manifest.generator,
            fixtures: fixtures
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(canonical)
        data.append(0x0A)
        return data
    }
}
