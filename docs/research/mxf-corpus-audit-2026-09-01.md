# MXF Corpus Audit

**Date:** 2026-09-01  
**Scope:** Existing MXF corruption handlers as candidates for PlayPlayPlay's deterministic adversarial parser corpus.

## Executive Summary

VideoCorruptor currently provides five deterministic MXF mutations. They are useful for exploratory robustness testing, but none yet forms a complete, self-describing parser fixture. Two primarily test behavior above the structural parser (essence and KLV-key corruption), two can exercise structural navigation but need more precise variants (BER length and partition offset), and one should be replaced with field-aware index mutation (index scrambling).

| Existing mutation | Primary layer exercised | Corpus value | Recommendation |
|---|---|---:|---|
| Essence byte corruption | Codec/essence consumer | Low for MXF parser | Keep as decoder/integration fixture |
| KLV-key corruption | KLV classification/discovery | Medium | Refine into single-key controlled variants |
| BER-length shortening | KLV framing/bounds | High | Split into explicit malformed and inconsistent-length cases |
| Footer-partition offset zeroing | Partition navigation/fallback | Medium | Keep, then add out-of-range and cyclic offsets |
| Index-table scrambling | Index metadata parsing | Low in current form | Replace with field-aware index mutations |

All random mutations use a per-corruption RNG derived from the master seed, so output is repeatable for the same input bytes, corruption type, seed, and severity. The generated result does not currently record exact changed offsets, original/new values, expected parser error, or source-file digest; those are required for a durable corpus manifest.

## 1. Essence Byte Corruption

### Current behavior

- Selects every KLV classified as picture essence.
- Skips a random 64–128 bytes at the start of each value.
- XORs randomly selected payload bytes. Severity controls the attempted mutation count from approximately 0.5% to 30%.
- Leaves KLV keys and BER lengths unchanged.

### Audit

This generally preserves MXF container framing. A bounded MXF reader should still enumerate the same KLV elements and lengths. Failures are more likely to occur in a codec decoder or media-validation layer, so this is not a strong structural-parser fixture.

The handler samples positions with replacement. Consequently, fewer distinct bytes may be changed than the reported count, and repeated XORs can alter the same byte multiple times. It also assumes that skipping 64–128 bytes protects a codec header; that is not codec-aware and may skip an entire small essence value.

### Recommendation

Keep this as an integration fixture named along the lines of `valid-container_corrupt-picture-essence`. Record the selected element and exact byte offsets. For a parser-only corpus, assert successful bounded traversal rather than an error. Add codec-aware corruption separately if decoder behavior matters.

## 2. KLV-Key Corruption

### Current behavior

- Selects picture-essence elements recognized by VideoCorruptor's classifier.
- Chooses a severity-dependent subset after a seeded shuffle.
- XORs byte 12 of each selected 16-byte key with `0xFF`.
- Leaves the SMPTE preamble, BER length, and value unchanged.

### Audit

This is deterministic and preserves KLV framing, but the resulting key is usually still a syntactically shaped 16-byte UL. It tests whether a consumer treats an unknown or reclassified essence key safely; it does not necessarily test rejection of a malformed KLV key.

Because only elements already recognized as picture essence can be targeted, the fixture depends on the narrow classifier matching the source encoding. At moderate severity it also changes many keys, making the first causal failure less precise.

### Recommendation

Refine this into one-change fixtures:

1. Unknown-but-well-formed essence UL.
2. Invalid SMPTE preamble byte.
3. Picture key changed to a known sound/data item type.
4. Duplicate or missing expected picture-element key.

Each fixture should identify the exact KLV offset and state whether the expected behavior is `unknown key skipped`, `wrong classification`, or a specific structural error.

## 3. BER-Length Shortening

### Current behavior

- Targets every recognized picture-essence KLV.
- Replaces the declared value length with a shorter seeded value while leaving the payload and following bytes in place.
- Attempts to encode the replacement in the original BER field width and zeroes unused bytes in that field.

### Audit

This has the highest immediate value for bounded-reader testing because the declared endpoint no longer coincides with the next real KLV boundary. A sequential reader will resume inside essence bytes and must remain bounded and terminate safely.

However, it is an inconsistent-length fixture rather than necessarily malformed BER. The replacement encoding can be non-canonical while still decodable. If the new value requires fewer length octets, the encoder changes the BER length-of-length but leaves zero bytes behind before the payload; those zeros become value bytes under the new interpretation. The mutation also changes every picture element, obscuring which mismatch produces the observed failure.

### Recommendation

Retain the current case as `declared-length-shorter-than-payload`, but generate a single targeted KLV. Add explicit variants for:

- BER long form with zero length-of-length (`0x80`, indefinite/reserved form).
- Length-of-length greater than eight.
- BER field truncated at EOF.
- Declared value length extending beyond EOF.
- Declared length causing integer-addition overflow.
- Non-minimal long-form encoding, with an explicit accept/reject policy.
- Zero-length value where the element requires content.

The expected outcome should be tied to a named bounded-reader error, not merely “parse failure.”

## 4. Footer-Partition Offset Zeroing

### Current behavior

- Selects the first element classified as a partition pack, assumed to be the header.
- Zeros eight bytes at value offset `+24`, the `FooterPartition` field.
- Does not verify that the selected partition is actually a header partition or that the original value was nonzero.

### Audit

Zero can legitimately mean that no footer partition is present or advertised. Therefore this mutation may create a recoverable/incomplete MXF rather than an invalid one, and it can be a no-op when the field is already zero. Its main value is testing fallback and missing-footer behavior.

The current selection rule is weaker than the parser's available `parseHeaderPartition` logic: “first partition pack” is not proof of a header. The mutation also cannot model bad nonzero offsets or cycles, which are more important to an adversarial bounded reader.

### Recommendation

Keep it as a semantic fixture only when the source has a real footer and verify the changed value. Add controlled variants for:

- Footer offset equal to EOF.
- Footer offset beyond EOF.
- Footer offset into the middle of a KLV value.
- Footer offset pointing to a non-partition KLV.
- Footer offset pointing back to the header/self.
- `PreviousPartition` self-cycle and two-partition cycle.
- `ThisPartition` inconsistent with the partition's physical offset.

Traversal must use a visited-offset set and a strict hop/count bound.

## 5. Index-Table Scrambling

### Current behavior

- Treats the complete value of every recognized index-table KLV as undifferentiated 8-byte blocks.
- Swaps approximately one quarter as many random block pairs as there are blocks.
- Does not use severity, parse local-set tags, or distinguish identifiers, edit rates, durations, counts, and index entries.

### Audit

This is deterministic but not surgically meaningful. Random swaps can corrupt local-set tags and lengths as readily as stream offsets, so the fixture's actual invariant and expected error cannot be known without reparsing the result. Random selection can choose the same block or undo earlier swaps, and successful execution does not guarantee a material or unique semantic change.

It is therefore unsuitable as the primary index corpus generator. It remains useful as fuzz-style robustness input.

### Recommendation

Rename or retain the current operation as `index-table-block-fuzz`. Build field-aware fixtures for:

- Index duration/count larger than available entries.
- Truncated index-entry array.
- Entry array element size inconsistent with slice/position-table counts.
- Stream offset beyond the essence container or file.
- Non-monotonic, duplicate, and backward stream offsets.
- `IndexSID`/`BodySID` mismatch.
- Invalid edit rate, including a zero denominator.
- Extreme slice/delta counts that test allocation and loop bounds.

## Cross-Cutting Corpus Requirements

Each generated fixture should have a sidecar manifest containing:

- Stable fixture ID and mutation version.
- SHA-256 of the pristine source and corrupted output.
- Master seed and severity, where applicable.
- Exact byte offsets and original/replacement bytes or decoded values.
- Structural precondition required of the source MXF.
- Expected PlayPlayPlay result: success, warning, or exact error case.
- Maximum bytes, elements, partitions, and traversal steps expected.

Corpus generation should fail if its precondition is absent or if the output is byte-identical to the source. For parser cases, prefer one intentional defect per fixture. Multi-defect and random-fuzz files can form a separate stress corpus.

## Coverage Against the Requested Adversarial Corpus

| Requested area | Covered now? | Notes |
|---|---|---|
| Malformed BER | Partial | Current case creates inconsistent shortened lengths, not a full malformed-BER matrix |
| Invalid offsets | Partial | Only `FooterPartition = 0`; no out-of-range or mid-element offsets |
| Invalid counts | No | Requires metadata/index field-aware mutation |
| Cycles | No | Requires partition-link fixtures and bounded traversal assertions |
| Missing structures | Partial | Zero footer reference only; no deliberate removal/absence matrix |
| Truncation | Generic only | File-level truncation exists, but boundary-specific MXF truncation does not |
| Cancellation | No | This is parser execution behavior, not a file mutation; test with large/adversarial fixtures and deterministic cancellation checkpoints |

## Recommended Implementation Order

1. Add a fixture manifest and mutation-change verification.
2. Convert BER corruption into explicit single-defect cases.
3. Add partition offset and cycle cases.
4. Implement a minimal local-set/index-table parser for count and offset mutations.
5. Add boundary truncation variants at key, BER, value, partition, metadata, index, and RIP boundaries.
6. Exercise PlayPlayPlay cancellation independently using large valid and adversarial inputs.

