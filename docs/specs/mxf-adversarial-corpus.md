# MXF Adversarial Corpus Specification

**Status:** Approved  
**Created:** 2026-09-01  
**Last Updated:** 2026-09-01

---

## Problem Statement

### What problem does this solve?

PlayPlayPlay's bounded MXF reader needs a repeatable adversarial corpus covering malformed BER, invalid offsets and counts, partition cycles, missing structures, boundary truncation, and cancellation. VideoCorruptor already has five seeded MXF mutations, but they are oriented toward interactive media corruption. They do not isolate one parser invariant per file, guarantee a material change, describe exact byte edits, or record the expected parser outcome.

Without a structured corpus, failures are difficult to reproduce and regressions cannot reliably distinguish safe rejection from hangs, excessive allocation, out-of-bounds reads, or decoder failures.

### Who has this problem?

- Developers testing PlayPlayPlay's MXF parser and bounded-reader behavior.
- Developers extending VideoCorruptor's MXF engine.
- Future consumers that need deterministic malformed MXF fixtures with machine-readable expectations.

### How is it handled today?

VideoCorruptor copies a source file and applies one of five mutations selected through the GUI. Batch manifests record filenames, type, severity, and seed, but not the exact edits, source hashes, mutation preconditions, or expected parser result. Some mutations affect many locations or target decoding rather than structural parsing.

---

## Proposed Solution

### One-Liner

Add a UI-independent MXF corpus generator that creates deterministic, single-defect fixtures and a versioned JSON manifest describing every edit and expected consumer behavior.

### Key Capabilities

1. Generate named, deterministic MXF fixtures from a known-good source.
2. Apply precise structural mutations to BER fields, partition links, local-set counts, index entries, and file boundaries.
3. Verify that every fixture satisfies its precondition and differs from its source exactly as declared.
4. Emit a manifest containing hashes, byte edits, semantic edits, limits, and expected outcomes.
5. Preserve the five existing interactive corruptions while classifying decoder and fuzz cases separately from parser conformance cases.
6. Allow PlayPlayPlay tests to consume the corpus without importing VideoCorruptor UI code.

### Approved Policy Decisions

- Support OP1a and OP-Atom first, using PlayPlayPlay's actual sample set and recording the profile of every source.
- Treat missing footer, RIP, and index structures according to the source profile; each fixture records an accepted, warning, or exact-error expectation.
- Check small synthetic fixtures and manifests into Git. Keep large or copyrighted fixtures outside Git and pin them by SHA-256.
- Require stable, machine-readable PlayPlayPlay error codes for approved parser-conformance fixtures.
- Accept otherwise-valid non-minimal BER encodings with a canonicality warning. Reject reserved/indefinite form, excessive length-of-length, overflow, truncation, and out-of-bounds values.
- Keep the generator as a Foundation-only VideoCorruptor service with JSON as the PlayPlayPlay boundary. A CLI may follow the service and tests.
- Treat essence corruption as decoder integration and block-level index scrambling as fuzz stress; parser-conformance fixtures are precise and normally contain one semantic defect.
- Test cancellation inside PlayPlayPlay at deterministic checkpoints; cancellation is an execution property rather than a malformed-file class.

### Primary Workflow

1. A developer supplies one or more valid, redistributable MXF source files.
2. The corpus generator scans each source and determines which fixture preconditions it satisfies.
3. For each requested case, it copies the source, applies one intentional defect, and records the exact mutation.
4. The generator reparses or inspects the output to verify the intended defect and rejects byte-identical or ambiguous output.
5. It writes fixtures and a sorted `manifest.json` into a corpus directory.
6. PlayPlayPlay loads each manifest entry, runs the bounded reader with declared limits, and compares the observed result with the consumer-specific expected result.

### Output Layout

```text
mxf-corpus/
├── manifest.json
├── sources/
│   └── source-op1a.mxf
└── fixtures/
    ├── ber-declared-length-beyond-eof.mxf
    ├── partition-footer-offset-beyond-eof.mxf
    ├── partition-previous-self-cycle.mxf
    └── index-entry-count-exceeds-payload.mxf
```

Source inclusion is configurable. If source files cannot be redistributed, the manifest must still contain the required source SHA-256 and reject generation from nonmatching input.

---

## Scope and Terminology

### Corpus Classes

| Class | Purpose | Expected behavior |
|---|---|---|
| `parserConformance` | One precise structural defect | Exact success/warning/error contract |
| `decoderIntegration` | Structurally traversable file with damaged essence | Parser succeeds; decoder may reject or report damage |
| `fuzzStress` | Multiple or broad seeded mutations | Must terminate safely within declared limits; exact error optional |
| `cancellation` | Large or adversarial workload used to interrupt parsing | Must return cancellation promptly and safely |

Only `parserConformance` fixtures are required to contain exactly one intentional defect.

### Definition of Deterministic

For identical generator version, source bytes, fixture ID, parameters, and seed, both the output bytes and canonical manifest entry must be identical. Timestamps and output paths must not participate in deterministic content.

### Definition of Bounded

A consumer must enforce configurable limits for input bytes, KLV elements, BER length, allocation size, local-set items, partition hops, visited offsets, and cancellation checks. A fixture may exercise one bound but must not require unbounded work to classify.

---

## Functional Requirements

### FR-1: UI-Independent Generator

Implement corpus generation in Foundation-only models and services. SwiftUI/AppKit views may invoke the service later, but mutation and manifest code must not depend on UI state.

Suggested structure:

```text
Services/MXFCorpus/
├── MXFCorpusGenerator.swift
├── MXFFixtureDefinition.swift
├── MXFFixtureManifest.swift
├── MXFMutation.swift
├── MXFMutationRecorder.swift
├── MXFStructuralInspector.swift
└── Mutations/
    ├── BERMutations.swift
    ├── PartitionMutations.swift
    ├── IndexMutations.swift
    ├── MissingStructureMutations.swift
    └── TruncationMutations.swift
```

The existing `MXFCorruptor` remains the interactive handler. Shared low-level mutation functions may be extracted, but corpus definitions must not call broad mutations whose target set is implicit.

### FR-2: Fixture Definition

Each fixture definition must declare:

- Stable reverse-DNS-style or dotted ID, such as `mxf.ber.lengthBeyondEOF.v1`.
- Human-readable title and rationale.
- Corpus class.
- Mutation schema version.
- Required source characteristics.
- Target-selection rule.
- Parameters and optional seed.
- Expected structural condition after mutation.
- Default consumer-independent outcome category.
- Recommended reader limits.

Fixture IDs are immutable. A behavior change requires a version suffix increment.

### FR-3: Preconditions

Preconditions must be evaluated before copying or mutating a source. Examples include:

- At least one partition pack exists.
- A nonzero footer offset points to a footer partition.
- At least two partitions exist.
- A picture-essence KLV uses a BER field of the required width.
- An index-table segment contains the required local-set field.
- A RIP exists.

A missing precondition produces `notApplicable`, not a corrupted output or generic failure. The reason must be included in the generation report.

### FR-4: Target Selection

Parser-conformance fixtures must select a target deterministically by structural identity, not by incidental collection order alone. The target record must include its physical offset and classification. Randomized target selection is allowed only when a seed is declared and the exact selected target is recorded.

### FR-5: Mutation Recording

Every mutation must produce one or more edit records:

```swift
struct MXFByteEdit: Codable, Sendable {
    let offset: UInt64
    let originalHex: String
    let replacementHex: String
    let field: String?
}
```

For truncation, record the original size and retained size rather than materializing all removed bytes in the manifest. For semantic numeric fields, also record the original and replacement unsigned/signed values.

Overlapping edits are forbidden unless a fixture explicitly declares a multi-step transformation and the recorder can express the order.

### FR-6: Mutation Verification

After writing a fixture, the generator must verify:

- The output hash differs from the source hash.
- Every recorded original byte matched the source before editing.
- Every recorded replacement byte appears at the declared output offset.
- No bytes outside declared edits changed, except bytes removed by truncation.
- The expected structural postcondition holds where it can be inspected safely.
- The source file remains unchanged.

Failure of any verification deletes or quarantines the incomplete output and marks generation failed. It must never be listed as a valid fixture.

### FR-7: Manifest

Create a separate corpus manifest rather than extending `BatchManifest`, because batch UI results and parser-test fixtures have different compatibility requirements.

Minimum JSON shape:

```json
{
  "schemaVersion": 1,
  "generator": {
    "name": "VideoCorruptor",
    "version": "1.0.0"
  },
  "fixtures": [
    {
      "id": "mxf.ber.lengthBeyondEOF.v1",
      "class": "parserConformance",
      "source": {
        "file": "source-op1a.mxf",
        "sha256": "...",
        "size": 123456
      },
      "output": {
        "file": "ber-declared-length-beyond-eof.mxf",
        "sha256": "...",
        "size": 123456
      },
      "seed": null,
      "edits": [
        {
          "offset": 4096,
          "originalHex": "83010000",
          "replacementHex": "83ffffff",
          "field": "klv.valueLength"
        }
      ],
      "expected": {
        "category": "invalidLength",
        "consumerCode": null
      },
      "limits": {
        "maxInputBytes": 200000,
        "maxKLVElements": 10000,
        "maxPartitionHops": 128
      }
    }
  ]
}
```

Requirements:

- Encode 64-bit offsets, sizes, seeds, and limits as decimal strings if JSON consumers cannot preserve unsigned 64-bit precision; choose one representation for schema version 1 and test it cross-language.
- Sort fixtures by ID and edits by offset.
- Use lowercase hexadecimal with no prefix.
- Use relative paths only; reject path traversal.
- Use ISO 8601 only for noncanonical run metadata outside the deterministic fixture entries.

### FR-8: Hashing

Use CryptoKit SHA-256 with streaming file reads. Do not load large sources solely to calculate hashes. Hashes are lowercase hexadecimal.

### FR-9: Atomic Output

Generate into a temporary sibling directory and move the completed corpus into place only after all requested fixtures and the manifest validate. Existing corpus output must not be silently overwritten. An explicit replace option may use a recoverable backup strategy.

### FR-10: Cancellation

Corpus generation must be asynchronous and cooperative:

- Check cancellation before scanning a source, before each fixture, during large streaming copies/hashes, and inside potentially long element loops.
- On cancellation, close handles, remove incomplete temporary outputs, retain the previous completed corpus, and return `CancellationError`.
- Do not encode cancellation as an ordinary failed fixture.

Cancellation corpus tests for PlayPlayPlay are consumer tests, not malformed-file mutations. The manifest may identify fixtures suitable for cancellation and recommended checkpoints or workloads, but it cannot prescribe wall-clock timing as deterministic file behavior.

---

## Required Fixture Matrix

### P0: BER Framing

| Fixture ID suffix | Mutation | Expected category |
|---|---|---|
| `ber.indefiniteForm.v1` | Replace BER first byte with `0x80` | `invalidBER` |
| `ber.lengthOfLengthTooLarge.v1` | Set length-of-length to 9 or greater | `invalidBER` |
| `ber.headerTruncated.v1` | Truncate inside a long-form BER field | `unexpectedEOF` |
| `ber.valueBeyondEOF.v1` | Declare value length beyond remaining bytes | `invalidLength` |
| `ber.lengthAdditionOverflow.v1` | Encode a length that overflows endpoint arithmetic | `integerOverflow` or `limitExceeded` |
| `ber.nonMinimalLongForm.v1` | Encode a small value in non-minimal long form | Accepted with canonicality warning |
| `ber.zeroRequiredValue.v1` | Set a required element's value length to zero | `invalidLength` or missing semantic content |
| `ber.shorterThanPayload.v1` | Retain current shortened-length concept on one KLV | Safe resynchronization failure or unknown data handling |

### P0: Partition Offsets and Cycles

| Fixture ID suffix | Mutation | Expected category |
|---|---|---|
| `partition.footerMissing.v1` | Set a verified nonzero footer offset to zero | Successful fallback, warning, or `missingFooter` |
| `partition.footerAtEOF.v1` | Point footer exactly to EOF | `invalidOffset` |
| `partition.footerBeyondEOF.v1` | Point footer beyond file size | `invalidOffset` |
| `partition.footerInsideValue.v1` | Point footer into an existing KLV value | `invalidPartition` |
| `partition.footerWrongKey.v1` | Point footer to a non-partition KLV | `invalidPartition` |
| `partition.previousSelfCycle.v1` | Set a partition's previous offset to itself | `partitionCycle` |
| `partition.previousTwoNodeCycle.v1` | Make two partitions reference one another | `partitionCycle` |
| `partition.thisOffsetMismatch.v1` | Set `ThisPartition` unequal to its physical location | `invalidOffset` |

Cycle fixtures intentionally require two numeric edits only when the valid source does not already contain the needed reciprocal link. This is still one semantic defect.

### P0: Counts and Allocation Bounds

These cases require parsing MXF local sets and relevant batch/array encodings rather than treating values as arbitrary 8-byte blocks.

| Fixture ID suffix | Mutation | Expected category |
|---|---|---|
| `count.localSetItemExceedsValue.v1` | Local item length exceeds enclosing set | `invalidLength` |
| `count.batchExceedsPayload.v1` | Batch count exceeds available entries | `invalidCount` |
| `count.batchItemSizeZero.v1` | Set batch element size to zero with nonzero count | `invalidCount` |
| `count.batchMultiplicationOverflow.v1` | Count × item size overflows or exceeds limit | `integerOverflow` or `limitExceeded` |
| `count.indexEntryExceedsPayload.v1` | Index entry count exceeds available entries | `invalidCount` |
| `count.sliceDeltaExtreme.v1` | Set slice/delta count above configured maximum | `limitExceeded` |

### P0: Missing Structures

| Fixture ID suffix | Mutation | Expected category |
|---|---|---|
| `missing.headerPartition.v1` | Invalidate only the header partition key | `missingHeaderPartition` |
| `missing.footerPartition.v1` | Remove/truncate a verified footer and update nothing else | `missingFooter` or safe fallback |
| `missing.rip.v1` | Truncate exactly before a verified RIP | Successful scan with warning or `missingRIP` |
| `missing.index.v1` | Invalidate a verified required index-table key | `missingIndex` or supported no-index path |
| `missing.requiredMetadataSet.v1` | Invalidate one selected required metadata-set key | Named missing-structure error |

Whether footer, RIP, or index absence is fatal depends on the supported MXF profile. The source profile and expected policy must be resolved before marking these fixtures approved.

### P0: Boundary Truncation

Generate truncation at structurally derived boundaries, not random percentages:

- Inside a 16-byte KLV key.
- Immediately after a complete key.
- Inside a long-form BER field.
- Immediately after a complete BER field.
- One byte before a declared value ends.
- Between complete KLV triplets.
- Inside a partition pack fixed field.
- Inside a local-set item header and value.
- Inside an index entry array.
- Inside and immediately before the RIP.

Each truncation fixture records the containing element, boundary description, original size, and retained size. Expected outcomes distinguish a clean end between complete optional elements from an unexpected EOF inside a required element.

### P1: Field-Aware Index Cases

| Fixture ID suffix | Mutation | Expected category |
|---|---|---|
| `index.streamOffsetBeyondEssence.v1` | Set one entry offset outside essence/file bounds | `invalidOffset` |
| `index.streamOffsetsBackward.v1` | Make one offset lower than its predecessor | Policy-defined invalid/nonmonotonic index |
| `index.streamOffsetsDuplicate.v1` | Duplicate adjacent offsets | Policy-defined invalid index |
| `index.sidMismatch.v1` | Make IndexSID inconsistent with partition/index references | `referenceMismatch` |
| `index.bodySIDMismatch.v1` | Point index at nonexistent/wrong body stream | `referenceMismatch` |
| `index.editRateZeroDenominator.v1` | Set edit-rate denominator to zero | `invalidRate` |

### P1: Existing Mutation Compatibility

- Keep essence byte corruption as `decoderIntegration`.
- Replace broad KLV-key corruption with precise key variants for `parserConformance`; retain broad form as `fuzzStress`.
- Retain BER shortening as a single-target explicit case.
- Retain footer offset zeroing only when its nonzero-footer precondition passes.
- Rename existing index scrambling conceptually to index-table block fuzzing; do not treat it as an index conformance case.

---

## Structural Inspector Requirements

The existing `MXFParser` is sufficient for scanning simple KLV triplets and reading fixed partition fields, but corpus generation also requires a bounded structural inspector.

### Required additions

- Report malformed/truncated KLV candidates instead of silently skipping invalid BER.
- Distinguish header, body, and footer partition pack keys.
- Parse all fixed partition-pack fields with checked arithmetic.
- Parse local-set tag/length/value items with enclosing-value bounds.
- Parse MXF batch headers with checked count × element-size arithmetic.
- Parse the subset of index-table fields needed for targeted mutation.
- Identify exact physical offsets for every parsed field.
- Expose diagnostics without allocating based on untrusted counts.

The production parser and corpus inspector may share primitives, but the generator must not use unsafe parsing assumptions to create adversarial files.

---

## API Sketch

Names are illustrative; behavior is normative.

```swift
struct MXFCorpusRequest: Sendable {
    let sources: [URL]
    let fixtureIDs: Set<String>?
    let outputDirectory: URL
    let masterSeed: UInt64
    let includeSources: Bool
}

struct MXFCorpusGenerator: Sendable {
    func generate(_ request: MXFCorpusRequest) async throws -> MXFCorpusReport
}

protocol MXFFixtureMutation: Sendable {
    var definition: MXFFixtureDefinition { get }

    func evaluate(
        source: MXFInspectedFile
    ) -> FixtureApplicability

    func apply(
        to workingFile: URL,
        source: MXFInspectedFile,
        rng: inout SeededRNG
    ) async throws -> MXFMutationRecord
}
```

Mutations receive a dedicated sub-seed derived from master seed plus fixture ID. Adding or removing another fixture must not change existing fixture bytes.

---

## PlayPlayPlay Integration Contract

VideoCorruptor owns fixture construction and consumer-independent expected categories. PlayPlayPlay owns the mapping from those categories to its concrete Swift error cases.

Recommended consumer-side adapter:

```swift
struct ExpectedMXFResult: Codable {
    let category: String
    let consumerCode: String?
}
```

During initial corpus validation, PlayPlayPlay writes or verifies `consumerCode` for every approved fixture. A fixture is not considered fully integrated until its expected result is explicit. “Any error” is insufficient for parser-conformance fixtures.

Every PlayPlayPlay corpus test must assert:

- The fixture SHA-256 matches the manifest before parsing.
- Parsing returns or throws the declared result.
- No read occurs outside the fixture's byte bounds.
- Configured element/allocation/partition limits are honored.
- Cycle cases terminate through cycle detection or hop limits.
- Cancellation cases return cancellation rather than a parse-domain error when cancellation wins.

---

## Acceptance Criteria

### P0: Deterministic Generation

- [ ] Given identical source bytes, generator version, fixture ID, seed, and parameters, when a corpus is generated twice, then every corresponding fixture SHA-256 and canonical manifest entry is identical.
- [ ] Given a different source hash, when generation is requested for a source-pinned fixture, then generation stops with a source-mismatch error before mutation.
- [ ] Given an applicable fixture, when generation succeeds, then the output differs from the source and all differences are represented by its mutation record.
- [ ] Given a fixture whose precondition is absent, when generation runs, then it reports `notApplicable` with a specific reason and emits no fixture file.
- [ ] Given the same master seed and existing fixture ID, when unrelated fixture definitions are added or removed, then that fixture's output remains unchanged.

### P0: Safety and Integrity

- [ ] Given any corpus mutation, when it is applied, then the pristine source file's size, SHA-256, and bytes remain unchanged.
- [ ] Given an edit whose expected original bytes do not match, when mutation begins, then it fails before writing a completed fixture.
- [ ] Given an output path containing traversal or escaping the corpus root, when generation validates the request, then it rejects the path.
- [ ] Given generation fails or is cancelled, when cleanup completes, then no incomplete corpus replaces the previous completed corpus.
- [ ] Given a numeric length, count, or endpoint, when it is inspected, then arithmetic overflow is detected before allocation, seeking, or indexing.

### P0: Required Coverage

- [ ] Given suitable sources, when the P0 suite is generated, then it contains all applicable BER, partition-offset/cycle, count, missing-structure, and boundary-truncation cases listed above.
- [ ] Given a BER fixture, when its mutation is inspected, then exactly one declared BER/framing defect is present.
- [ ] Given a cycle fixture, when its partition graph is inspected, then the declared cycle exists and unrelated partition fields are unchanged.
- [ ] Given a count fixture, when its enclosing payload is inspected, then the declared count/size inconsistency is reproducible without allocating from the corrupted count.
- [ ] Given a truncation fixture, when its size is inspected, then it ends at the exact declared structural boundary.

### P0: Manifest

- [ ] Given a completed corpus, when `manifest.json` is decoded, then every fixture path exists beneath the corpus root and every file's size and SHA-256 match.
- [ ] Given a parser-conformance entry, when the manifest is validated, then it has a stable ID, source identity, output identity, edit record, expected category, and reader limits.
- [ ] Given two logically identical corpus runs, when manifests are serialized canonically, then nondeterministic timestamps and absolute paths do not alter fixture entries.

### P0: PlayPlayPlay Validation

- [ ] Given each approved parser-conformance fixture, when PlayPlayPlay parses it, then the observed success/warning/exact error equals the recorded consumer expectation.
- [ ] Given an invalid offset or length beyond EOF, when PlayPlayPlay parses it, then no read is attempted outside file bounds.
- [ ] Given an extreme count, when PlayPlayPlay parses it, then it returns overflow/limit failure without allocating proportional to the corrupted count.
- [ ] Given a partition cycle, when PlayPlayPlay traverses it, then parsing terminates within the configured partition-hop bound.

### P0: Cancellation

- [ ] Given a large valid fixture, when its parse task is cancelled at a deterministic test checkpoint, then PlayPlayPlay returns cancellation and releases file resources.
- [ ] Given a cycle, extreme-count, or resynchronization fixture, when cancellation is requested during parsing, then cancellation is observed without waiting for the adversarial bound to be exhausted.
- [ ] Given corpus generation is cancelled during copy, hashing, inspection, or mutation, then it returns `CancellationError` and removes incomplete temporary output.

### P1: Existing Features

- [ ] Given the same source, seed, and severity, when an existing interactive MXF corruption is run after shared-code extraction, then its output remains deterministic.
- [ ] Given essence corruption output, when the structural reader scans it, then KLV framing remains unchanged unless the source itself was invalid.
- [ ] Given index block fuzzing, when the manifest is written, then it is classified as `fuzzStress`, not `parserConformance`.

---

## Testing Strategy

### Unit Tests

- BER decode/encode edge cases and canonicality policy.
- Checked addition and multiplication at `UInt64.max` boundaries.
- Partition-field physical offset calculation.
- Local-set and batch parsing under truncated and extreme inputs.
- Per-fixture sub-seed stability.
- Byte-edit application, overlap rejection, and verification.
- Canonical manifest encoding and path validation.

Use small in-memory synthetic KLV sequences for low-level tests. Do not require large binary fixtures for arithmetic and framing cases.

### Generator Integration Tests

- Generate representative fixtures from small checked-in synthetic MXF samples.
- Compare output hashes with golden expectations where stable.
- Confirm source immutability.
- Confirm not-applicable behavior across sources with different structures.
- Cancel at injected deterministic checkpoints rather than relying only on timing.

### Consumer Contract Tests

PlayPlayPlay runs all approved manifest entries and maps consumer-independent categories to exact parser results. These tests belong in PlayPlayPlay, while the corpus manifest remains generated and versioned here or in a separately versioned fixture package.

### Test Target Requirement

Add a macOS unit-test target to `01_Project/project.yml`. The current project has no test target; corpus implementation is not complete without automated tests for the mutation and manifest layers.

---

## Performance and Resource Limits

- Inspect and hash large files using bounded/streaming reads where practical.
- Do not create a `Data` copy of the entire file for mutations that touch fixed offsets or truncate at a known boundary.
- Default generation concurrency is serial until source and destination I/O behavior is measured. Parallelism may be added with an explicit maximum.
- Never allocate using an untrusted count or length before checking arithmetic and configured caps.
- Cancellation checks must occur during any loop that can scale with file size or element count.

No fixed wall-clock threshold is specified for parsing across developer hardware. Deterministic operation-count and byte-count bounds are preferred. A later benchmark spec may add performance budgets.

---

## Security and Data Handling

- Treat source MXFs and generated fixtures as untrusted binary input.
- Normalize and validate all output paths beneath the selected corpus root.
- Never follow manifest paths outside that root.
- Never modify source files in place.
- Do not include user file paths, usernames, or other machine-specific data in canonical manifests.
- Generated fixtures may contain source essence and metadata; redistribution requires rights to the source material.
- Avoid logging full metadata values that may contain identifying production information.

---

## Delivery Plan

### Phase 1: Foundation

- Add the test target.
- Add checked binary-reading helpers and structural diagnostics.
- Define fixture, edit-record, manifest, report, and expected-result models.
- Implement canonical serialization, SHA-256, atomic output, and verification.

### Phase 2: BER and Truncation

- Implement the P0 BER matrix.
- Implement structure-derived truncation boundaries.
- Validate with synthetic unit samples and at least one real valid MXF source.

### Phase 3: Partitions and Missing Structures

- Classify header/body/footer partition keys.
- Implement invalid offsets, self/two-node cycles, and missing partition/RIP cases.
- Add partition graph inspection and traversal-limit metadata.

### Phase 4: Counts and Index Tables

- Implement bounded local-set and batch inspection.
- Parse the minimum required index-table fields.
- Add P0 count cases and P1 field-aware index cases.
- Reclassify the existing block-scrambling operation as fuzz stress.

### Phase 5: Consumer Validation

- Generate the initial pinned corpus.
- Run it through PlayPlayPlay.
- Record exact consumer error codes and resolve profile-dependent expectations.
- Add cancellation contract tests in PlayPlayPlay.

### Phase 6: Optional Product Integration

- Expose corpus generation through a command-line executable or app UI only after the service and tests are stable.
- If a CLI is added, support listing fixture definitions, checking applicability, generating selected/all fixtures, and validating an existing corpus.

---

## Out of Scope

- A general-purpose coverage-guided fuzzer.
- Codec-aware repair or validation of corrupted essence.
- Guaranteeing identical decoder behavior across FFmpeg, AVFoundation, and professional NLEs.
- Full support for every MXF operational pattern in the first corpus release.
- Embedding PlayPlayPlay as a dependency of VideoCorruptor.
- Network distribution or automatic downloading of copyrighted source MXFs.
- GUI design for corpus generation in the initial implementation.
- Wall-clock cancellation guarantees independent of hardware and scheduling.

---

## Open Questions

| Question | Status | Proposed resolution |
|---|---|---|
| Which MXF profiles must be supported first? | Resolved | OP1a and OP-Atom from PlayPlayPlay's sample set; record profile per source |
| Are footer, RIP, and index absence fatal for each supported profile? | Resolved | Apply profile-aware policy and record accepted, warning, or exact-error expectation per fixture |
| Where will binary corpus files live? | Resolved | Check in a small synthetic core and manifests; keep large/copyrighted media external and pin by SHA-256 |
| Does PlayPlayPlay already expose stable error codes? | Resolved | Stable machine-readable codes are required; add or map them before approving individual fixtures |
| Should the first invocation surface be tests, CLI, or GUI? | Resolved | Build the service and test API first; CLI is the preferred optional automation surface |
| Should existing `MXFParser` become the production inspector? | Resolved | Share safe primitives, but add diagnostic/bounded inspection behavior rather than silently skipping malformed data |
| What is the BER non-minimal-encoding policy? | Resolved | Accept otherwise-valid non-minimal BER with a canonicality warning |

No policy question currently blocks implementation. Individual fixtures remain unapproved until their source-profile expectation and stable PlayPlayPlay result code are recorded.

---

## Definition of Done

The feature is complete when:

1. All P0 acceptance criteria pass in automated tests.
2. Every applicable P0 fixture is generated deterministically and validates against its manifest.
3. PlayPlayPlay records and passes an exact expected result for every approved parser-conformance fixture.
4. Cycle, overflow, out-of-bounds, and cancellation tests demonstrate bounded termination.
5. Existing interactive corruption behavior remains functional and deterministic.
6. Corpus schema version 1 and source redistribution/storage decisions are documented.

---

## Related

- [MXF corpus audit](../research/mxf-corpus-audit-2026-09-01.md)
- [Video corruption engine spec](video-corruption.md)
- [MXF corruption research](../research/video-corruption-mxf.md)
- [Current project state](../PROJECT_STATE.md)
- [2026-09-01 recovery session](../sessions/2026-09-01.md)
