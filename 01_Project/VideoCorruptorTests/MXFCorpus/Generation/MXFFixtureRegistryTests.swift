import XCTest
@testable import VideoCorruptor

final class MXFFixtureRegistryTests: XCTestCase {
    func testCompleteRegistryHasExactRequiredCoverageContract() throws {
        let registry = try MXFFixtureRegistry.complete()
        let ids = Set(try registry.selected(ids: nil).map(\.definition.id))

        XCTAssertEqual(MXFFixtureRegistry.requiredFixtureIDs.count, 45)
        XCTAssertEqual(ids, MXFFixtureRegistry.requiredFixtureIDs)
        XCTAssertEqual(ids.filter { $0.hasPrefix("ber.") }.count, 8)
        XCTAssertEqual(ids.filter { $0.hasPrefix("partition.") }.count, 8)
        XCTAssertEqual(ids.filter { $0.hasPrefix("count.") }.count, 6)
        XCTAssertEqual(ids.filter { $0.hasPrefix("mxf.missing.") || $0.hasPrefix("missing.") }.count, 5)
        XCTAssertEqual(ids.filter { $0.hasPrefix("mxf.truncation.") }.count, 12)
        XCTAssertEqual(ids.filter { $0.hasPrefix("index.") }.count, 6)
    }

    func testControlledSourcesEvaluateEveryCaseWithExplicitResult() throws {
        for profile in SyntheticMXFProfile.allCases {
            let inspected = MXFStructuralInspector().inspect(data: SyntheticMXFBuilder.make(profile))
            let declaration: MXFMissingStructureSourceDeclaration = profile == .op1a ? .op1a : .opAtom
            let fixtures = try MXFFixtureRegistry.complete(
                declarations: .init(missingStructures: declaration)
            ).selected(ids: nil)

            let results = fixtures.map { ($0.definition.id, $0.evaluate(source: inspected)) }
            XCTAssertEqual(results.count, 45, profile.rawValue)
            XCTAssertEqual(results.filter { if case .applicable = $0.1 { true } else { false } }.count, 19,
                           profile.rawValue)
            XCTAssertEqual(results.filter { if case .notApplicable = $0.1 { true } else { false } }.count, 26,
                           profile.rawValue)
            for (id, result) in results {
                if case .notApplicable(let reason) = result {
                    XCTAssertFalse(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id)
                }
            }
        }
    }
}
