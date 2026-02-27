# Project State

## Identity
- **Project:** VideoCorruptor
- **One-liner:** macOS tool that intentionally corrupts video files to test VideoAnalyzer and VCR
- **Tags:** macOS, SwiftUI, developer-tool, video, testing
- **Started:** 2026-02-26

## Current Position
- **Funnel:** build
- **Phase:** implementation
- **Focus:** Implement corruption expansion plan (19 → 41 types, 8 waves)
- **Status:** active
- **Last updated:** 2026-02-26

## Funnel Progress

| Funnel | Status | Gate |
|--------|--------|------|
| **Define** | done | Corruption types mapped to VideoAnalyzer issues |
| **Plan** | done | Architecture decided, spec written |
| **Build** | active | MVP done, expansion plan ready |

## Phase Progress
```
[##############......] 70% - 19 corruption types, MXF support, engine refactored
```

| Phase | Status | Tasks |
|-------|--------|-------|
| Discovery | done | Sibling project analysis |
| Planning | done | Spec + decisions |
| Implementation | done | Core engine + GUI |
| Expansion | **next** | 8-wave plan: 22 new corruption types (see CORRUPTION-EXPANSION-PLAN.md) |
| Testing | active | First real test passed, date fix applied |
| Polish | pending | Severity controls, batch mode |

## Readiness

| Dimension | Status | Notes |
|-----------|--------|-------|
| Features | 🔶 WIP | 19 corruption types (MP4+MXF), frame map builder, KLV parser |
| UI/Polish | 🔶 WIP | Functional, needs refinement |
| Testing | 🔶 WIP | First test done; VideoAnalyzer crashes on some outputs |
| Docs | ✅ done | Directions, spec, decisions, research (3 docs), expansion plan |
| Distribution | ⚪ — | Dev tool, may not need distribution |

## Active Decisions
- 2026-02-26: Custom MP4 parser over ffmpeg (no external deps)
- 2026-02-26: Copy-only operations (never modify originals)
- 2026-02-26: XcodeGen for project management (consistent with sibling projects)
- 2026-02-26: One flat CorruptionType enum with supportedFormats (not per-format enums)
- 2026-02-26: Protocol-based engine dispatch (CorruptionHandler → FileCorruptor, MP4Corruptor, MXFCorruptor)

## Blockers
None

---
*Updated by Claude. Source of truth for project position.*
