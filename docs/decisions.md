# Decisions Log

This file tracks the WHY behind technical and design decisions.

---

## Decisions

### 2026-02-26 - Custom MP4 Parser Over ffmpeg
**Context:** Need to surgically corrupt specific atoms in MP4/MOV containers for test file generation.
**Options Considered:**
1. **ffmpeg** - Shell out to ffmpeg for track removal, timestamp manipulation
   - Pros: Proven, handles many formats
   - Cons: External dependency, overkill for corruption, less byte-level control
2. **AVFoundation** - Use Apple's media framework
   - Pros: Native, no deps
   - Cons: Great for reading, not for surgical byte-level corruption
3. **Custom Swift MP4 parser + binary manipulation**
   - Pros: Full control, no deps, precise atom targeting
   - Cons: Limited to MP4/MOV (acceptable for this tool)

**Decision:** Custom Swift MP4 parser + binary manipulation
**Rationale:** MP4 atoms are simple (size + type + payload). A lightweight parser gives surgical control over exactly what gets corrupted. No encoding/decoding needed - just structural manipulation.
**Consequences:** Adding MKV/WebM support would need a separate parser. Acceptable since VideoAnalyzer and VCR primarily target MP4/MOV.

### 2026-02-26 - Copy-Only File Operations
**Context:** Tool corrupts files - need safety guarantees.
**Decision:** Always work on copies. Never modify the original file.
**Rationale:** This is a testing tool. Accidentally destroying a source file would defeat its purpose.

### 2026-02-26 - XcodeGen for Project Management
**Context:** Starting a new Xcode project alongside VideoAnalyzer and VCR.
**Decision:** Use XcodeGen with project.yml, consistent with sibling projects.
**Rationale:** Keeps xcodeproj out of version control, same tooling as VideoAnalyzer.

### 2026-09-01 - MXF Corpus Architecture and Validation Policy
**Context:** PlayPlayPlay needs a deterministic adversarial MXF corpus for malformed BER, offsets, counts, cycles, missing structures, truncation, and cancellation. VideoCorruptor already has five broad MXF mutations, but they do not isolate parser invariants or record exact expected results.

**Options Considered:**
1. **Build fixture generation directly into PlayPlayPlay**
   - Pros: Consumer errors and fixtures live together
   - Cons: Duplicates VideoCorruptor's mutation knowledge and couples test construction to the parser under test
2. **Use VideoCorruptor's existing GUI mutations unchanged**
   - Pros: Minimal implementation work
   - Cons: Broad mutations, incomplete structural coverage, and no exact mutation or result contract
3. **Add a UI-independent corpus service to VideoCorruptor with a manifest boundary**
   - Pros: Reuses binary tooling, isolates single defects, remains consumer-independent, and supports repeatable cross-project tests
   - Cons: Requires structural inspection, a new manifest schema, tests, and optional later CLI work

**Decision:** Implement a Foundation-only corpus-generation service in VideoCorruptor. It will emit deterministic, verified fixtures and versioned JSON manifests; PlayPlayPlay will map manifest categories to stable machine-readable error codes. Start with OP1a and OP-Atom sources. Use profile-aware missing-structure expectations, accept valid non-minimal BER with a canonicality warning, store small synthetic fixtures in Git, and pin external large or copyrighted fixtures by SHA-256. Treat essence damage as decoder integration, index block scrambling as fuzz stress, and cancellation as a PlayPlayPlay execution test at deterministic checkpoints.

**Rationale:** This creates a clean ownership boundary: VideoCorruptor owns precise malformed-file construction while PlayPlayPlay owns parser semantics. Exact edits, hashes, source profiles, and expected outcomes make failures reproducible without introducing a cross-project code dependency.

**Consequences:** VideoCorruptor needs a test target, bounded structural inspector, mutation recorder, canonical manifest, hashing, and atomic output. PlayPlayPlay must expose or map stable error codes. Parser-conformance fixtures normally contain one semantic defect; broad existing mutations remain useful but belong to separate integration/fuzz classes.

### 2026-09-01 - Bounded Inspection and Atomic Corpus Publication
**Context:** MXF sources may be large or adversarial, while the corpus generator must prove exact edits and never expose incomplete output. A whole-file inspection path would undermine the resource-bound contract even if hashing and copying were streamed.

**Options Considered:**
1. **Map or load the entire source for structural inspection**
   - Pros: Reuses the in-memory synthetic-test API directly
   - Cons: Memory behavior scales with hostile input and contradicts the corpus bounded-I/O contract
2. **Stream every value payload through the inspector**
   - Pros: Sequential access pattern
   - Cons: Unnecessary I/O because Wave 1 only needs structural boundaries and metadata
3. **Read bounded key/BER headers and seek across validated values**
   - Pros: Constant-size reads, checked endpoints, deterministic cancellation points, and no payload allocation
   - Cons: Requires a file-backed inspector alongside the in-memory synthetic-test API

**Decision:** Production corpus inspection uses `FileHandle` to read each 16-byte key and at most nine BER bytes, then seeks to the checked value endpoint. Generation occurs in a unique same-volume sibling staging directory. The final directory is published only after mutation verification, hashing, manifest validation, tree validation, and source revalidation all succeed; existing destinations are never replaced implicitly.

**Rationale:** This keeps memory and I/O behavior bounded independently of essence size while preserving precise physical spans. Atomic publication ensures consumers can observe either the previous complete corpus or the new complete corpus, never a partial tree.

**Consequences:** The inspector maintains both in-memory and file-backed entry points. Cancellation or any validation failure removes staging output, equal-size edits and truncations are verified exactly, and later fixture waves inherit a non-destructive transaction boundary.

### 2026-09-01 - Physical Partition Identity and Profile-Aware Absence
**Context:** Adversarial partition fixtures deliberately corrupt `ThisPartition`, previous/footer links, and structural presence. Treating declared offsets as identity would make the inspector trust the field under test, while treating footer, RIP, or index absence uniformly would impose behavior that differs between OP1a and OP-Atom.

**Options Considered:**
1. **Use `ThisPartition` as the partition map key and apply universal missing-structure outcomes**
   - Pros: Mirrors logical MXF references directly
   - Cons: A corrupt value can alias or hide physical packs, and profile-specific fallback behavior is lost
2. **Scan arbitrary bytes for partition-looking ULs after an invalid link**
   - Pros: May recover additional structures
   - Cons: Can misclassify essence bytes and makes work/resource bounds ambiguous
3. **Use physical KLV boundaries as identity and require typed profile declarations for absence policy**
   - Pros: Keeps corrupt fields observable, traversal bounded, and expected outcomes explicit
   - Cons: Fixtures without verified structure/profile evidence must return `notApplicable`

**Decision:** Partition nodes are keyed by physical KLV offsets and classified solely from their physical UL keys. `ThisPartition` remains a separately parsed value whose mismatch is diagnostic. Link resolution uses only known structural boundaries, with exact hop and visited-offset limits. Missing header/footer/RIP fixtures require an explicit OP1a or OP-Atom source declaration; missing index remains deferred until a verified index-key/local-set seam exists.

**Rationale:** The corpus must test corrupt references without trusting them and must never turn heuristic resynchronization or assumed profile policy into the fixture authority.

**Consequences:** Self- and two-node cycles terminate at exact operation counts, unrelated bytes remain verifiable, profile-sensitive outcomes are recorded in each definition, and unsupported or ambiguous sources are reported as `notApplicable`.

### 2026-09-02 - Declaration-Driven Local-Set and Index Semantics
**Context:** Count and index conformance fixtures must identify exact MXF local-set fields while remaining safe on malformed counts. Inferring semantics from unknown local tags or allocating from declared array sizes would make the fixture authority depend on the same hostile values it is meant to test.

**Options Considered:**
1. **Recognize common local tags heuristically**
   - Pros: Applies to more sources automatically
   - Cons: Primer-dependent tags can be source-specific, so a guessed field can create a mislabeled defect
2. **Parse arrays first and validate their counts afterward**
   - Pros: Simpler iteration code
   - Cons: A hostile count can drive overflow, excessive allocation, or work before validation
3. **Require explicit mappings and validate counts before constructing ranges**
   - Pros: Exact field provenance, deterministic applicability, and bounded behavior on tiny hostile buffers
   - Cons: Real sources need a verified declaration before these fixtures apply

**Decision:** Local-set and index inspection accepts caller-owned tag mappings and schemas only. Batch and entry counts are checked for multiplication overflow, configured element/allocation limits, and enclosing payload bounds before ranges, allocation, or entry walking. Mutations pin the expected source layout and revalidate it before applying same-width edits.

**Rationale:** The corpus must prove which field it changed and must remain bounded independently of untrusted count values. Explicit declarations make ambiguity visible as `notApplicable` instead of silently guessing.

**Consequences:** Synthetic and real source profiles must supply verified mappings. Count and index fixtures record exact set, tag, item, and subfield spans; huge counts in tiny inputs return typed bounded failures; and existing broad index scrambling remains a separate fuzz-stress behavior.

---
*Add decisions as they are made. Future-you will thank present-you.*
