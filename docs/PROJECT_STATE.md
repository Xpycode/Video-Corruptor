# Project State

## Identity
- **Project:** VideoCorruptor
- **One-liner:** macOS tool that intentionally corrupts video files to test VideoAnalyzer and VCR
- **Tags:** macOS, SwiftUI, developer-tool, video, testing
- **Started:** 2026-02-26

## Current Position
- **Funnel:** build
- **Phase:** implementation
- **Focus:** MXF adversarial corpus complete; macOS 26 toolbar rendering corrected and accepted
- **Status:** ready for the remaining manual seed, mixed-format batch, and blocker-gating checks
- **Last updated:** 2026-09-03 (toolbar accepted; full test suite green)

## Funnel Progress

| Funnel | Status | Gate |
|--------|--------|------|
| **Define** | done | Corruption types mapped to VideoAnalyzer issues |
| **Plan** | done | MXF corpus audit complete; implementation spec and policies approved |
| **Build** | done | Waves 0–6 complete; controlled corpus is generated, mapped, and approved |

## Phase Progress
```
[####################] 100% - all 33 corpus tasks complete
```

| Phase | Status | Tasks |
|-------|--------|-------|
| Discovery | done | Sibling project analysis |
| Planning | done | Spec + decisions |
| Implementation | done | Core engine + GUI |
| Expansion | **next** | 8-wave plan: 22 new corruption types (see CORRUPTION-EXPANSION-PLAN.md) |
| Testing | **next** | Manual: seed reproducibility, mixed-format batch, blocker gating |
| Polish | done | Seed system, severity controls, stacking, batch mode |

## Readiness

| Dimension | Status | Notes |
|-----------|--------|-------|
| Features | 🔶 WIP | 19 corruption types + seed/severity/stacking/batch |
| UI/Polish | ✅ done | Compact SAR-style toolbar accepted on macOS 26 |
| Testing | ✅ done | Wave 6 gate passes: 153 automated tests, 0 failures, 1 opt-in export skip |
| Docs | ✅ done | MXF corpus audit and approved implementation spec recorded |
| Distribution | ⚪ — | Dev tool, may not need distribution |

## Active Decisions
- 2026-02-26: Custom MP4 parser over ffmpeg (no external deps)
- 2026-02-26: Copy-only operations (never modify originals)
- 2026-02-26: XcodeGen for project management (consistent with sibling projects)
- 2026-02-26: One flat CorruptionType enum with supportedFormats (not per-format enums)
- 2026-02-26: Protocol-based engine dispatch (CorruptionHandler → FileCorruptor, MP4Corruptor, MXFCorruptor)
- 2026-02-27: CorruptionContext as inout value type over actor-based shared state (Swift 6 safe)
- 2026-02-27: Per-type sub-seed derivation via FNV-1a (type independence)
- 2026-02-27: Phase ordering for stacking (bitstream→file, inner layers first)
- 2026-02-27: Bounded TaskGroup concurrency (2 parallel) for batch processing
- 2026-09-01: Foundation-only deterministic MXF corpus service with JSON manifest boundary to PlayPlayPlay

## Blockers
None

## Latest Verification
- **2026-09-03:** The toolbar now uses the compact hidden-titlebar shell, 28-point SAR-style controls,
  correct leading/trailing placement, and macOS 26 shared-background suppression. Visual review passed;
  the Debug build succeeds and all 153 tests pass with the expected opt-in export skip.
- **2026-09-02:** Wave 6 complete. PlayPlayPlay validates the separate adversarial manifest through
  its real CBMX-backed structural path with stable errors, explicit resource budgets, and deterministic
  cancellation. Nineteen project-owned fixtures are approved: 10 accepted and 9 exact rejections;
  26 registry cases remain explicitly not applicable to the controlled source. VideoCorruptor builds
  and all 153 tests pass, with only the opt-in export test skipped. PlayPlayPlay passes all 100 tests,
  with three external-media tests skipped.
- **2026-09-02:** Wave 5 complete. Project-owned OP1a and OP-Atom sources have pinned hashes and
  rights provenance. The registry locks all 45 required cases; the controlled release generates
  19 structurally verified fixtures and reports 26 explicit not-applicable reasons. Two independent
  generations have identical trees and canonical manifests. Debug build succeeds and all 152 tests
  pass. No fixture is consumer-approved before PlayPlayPlay mapping.
- **2026-09-02:** Wave 4 complete. XcodeGen output is reproducible; Debug build succeeds; all
  144 tests pass. Bounded local-set/primer and batch inspection, five count fixtures, minimum
  index-table semantics, and seven field-aware index fixtures are verified with exact field spans.
- **2026-09-01:** Wave 3 complete. XcodeGen output is reproducible; Debug build succeeds; all
  118 tests pass. Partition classification/graph bounds, seven offset/cycle fixtures, profile-aware
  missing header/footer/RIP behavior, and partition fixed-field truncation are verified.
- **2026-09-01:** Wave 2 complete. XcodeGen output is reproducible; Debug build succeeds; all
  95 tests pass. Fourteen BER/truncation fixture IDs and output hashes are pinned by the canonical
  corpus golden; production corpus services retain bounded file I/O.
- **2026-09-01:** Wave 1 complete. XcodeGen output is reproducible; Debug build succeeds; all
  84 tests pass. Bounded streaming inspection, exact mutation verification, streaming copy/hash,
  deterministic cancellation, and atomic rollback/publish are gated before fixture definitions.
- **2026-09-01:** Wave 0 complete. XcodeGen output is reproducible; Debug build succeeds; all
  43 tests pass. Checked arithmetic/access, schema v1 round trips and validation, canonical manifest
  golden/path safety, and fixture-keyed seed independence are gated before file mutation work.

## Recovery Note
- **2026-09-01:** Re-cloned from GitHub after the old local checkout disappeared. The existing MXF
  engine is now audited and the corpus implementation spec is approved. Next, plan the generator
  foundation and its automated test target.

---
*Updated by Claude. Source of truth for project position.*
