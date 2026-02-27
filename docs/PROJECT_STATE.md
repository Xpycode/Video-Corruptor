# Project State

## Identity
- **Project:** VideoCorruptor
- **One-liner:** macOS tool that intentionally corrupts video files to test VideoAnalyzer and VCR
- **Tags:** macOS, SwiftUI, developer-tool, video, testing
- **Started:** 2026-02-26

## Current Position
- **Funnel:** build
- **Phase:** implementation
- **Focus:** UI polish (AppKit controls), then expansion wave 1
- **Status:** active
- **Last updated:** 2026-02-27 (session 5 — UI polish)

## Funnel Progress

| Funnel | Status | Gate |
|--------|--------|------|
| **Define** | done | Corruption types mapped to VideoAnalyzer issues |
| **Plan** | done | Architecture decided, spec written |
| **Build** | active | MVP done, 9 reliability fixes applied, expansion plan ready |

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
| Testing | 🔶 WIP | First test done; VideoAnalyzer crashes on some outputs |
| Docs | ✅ done | Directions, spec, decisions, research, README on GitHub |
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

## Blockers
None

---
*Updated by Claude. Source of truth for project position.*
