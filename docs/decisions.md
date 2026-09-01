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

---
*Add decisions as they are made. Future-you will thank present-you.*
