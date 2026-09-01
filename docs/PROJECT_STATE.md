# Project State

## Identity
- **Project:** VideoCorruptor
- **One-liner:** macOS tool that intentionally corrupts video files to test VideoAnalyzer and VCR
- **Tags:** macOS, SwiftUI, developer-tool, video, testing
- **Started:** 2026-02-26

## Current Position
- **Funnel:** build
- **Phase:** implementation
- **Focus:** Wave 2 of the MXF corpus plan: BER mutations and generic boundary truncation
- **Status:** active
- **Last updated:** 2026-09-01 (repository recovered for PlayPlayPlay MXF corpus work)

## Funnel Progress

| Funnel | Status | Gate |
|--------|--------|------|
| **Define** | done | Corruption types mapped to VideoAnalyzer issues |
| **Plan** | done | MXF corpus audit complete; implementation spec and policies approved |
| **Build** | active | Waves 0–1 complete; Wave 2 BER/truncation fixtures are next |

## Phase Progress
```
[################....] 82% - 19 types + 4 features + 9 reliability fixes
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
| UI/Polish | 🔶 WIP | AppKit buttons + toolbar style applied, toolbar rendering WIP |
| Testing | 🔶 WIP | Wave 1 gate passes: 84 automated tests, 0 failures |
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
