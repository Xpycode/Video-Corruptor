# Session History

## Active Project
VideoCorruptor - macOS tool for generating corrupted video test files

## Current Status
→ See [PROJECT_STATE.md](../PROJECT_STATE.md)

## Sessions

| Date | Focus | Outcome | Log |
|------|-------|---------|-----|
| 2026-09-03 | Checkpoint the MXF corpus and correct macOS toolbar rendering | Corpus work was pushed; the accepted SAR-style toolbar removes macOS 26 glass circles and preserves trailing placement. All 153 tests pass. Next: three manual acceptance checks. | [Log](2026-09-03.md) |
| 2026-09-02 | Complete and consumer-validate the adversarial MXF corpus | All seven waves complete: 19 controlled fixtures map to 10 accepted and 9 exact rejections; 153 producer tests pass. Next: PlayPlayPlay Release performance matrix. | [Log](2026-09-02.md) |
| 2026-09-02 | Complete Wave 4 local-set, count, and index semantics | Added bounded inspectors plus 12 exact count/index fixtures; Debug build and all 144 tests pass. Next: Wave 5 controlled sources and release validation. | [Log](2026-09-02.md) |
| 2026-09-01 | Build the adversarial MXF corpus through Wave 3 | Completed deterministic schema/generation, BER and truncation goldens, bounded partition graphs, offset/cycle fixtures, and profile-aware missing structures; 118 tests pass. Next: Wave 4 local sets, counts, and index semantics. | [log](2026-09-01.md) |
| 2026-02-27e | UI polish: AppKit controls | AppKitButton + AppKitToolbarButtonStyle, mode picker moved, processing overlay | [log](2026-02-27e.md) |
| 2026-02-27d | Reliability hardening | 9/9 fixes applied (2 critical, 4 high, 3 medium), clean build, pushed | [log](2026-02-27.md) |
| 2026-02-27c | Code review & fix plan | Verified 9 issues, rejected 3 false claims, saved fix plan | [log](2026-02-27.md) |
| 2026-02-27b | Docs & GitHub sync | Full README pushed to GitHub | [log](2026-02-27.md) |
| 2026-02-27 | Seed, severity, stacking, batch | 4 production features implemented, +1763 lines, clean build | [log](2026-02-27.md) |
| 2026-02-26d | Corruption expansion plan | Full 8-wave plan: 22 new types (19→41), parser gaps, fMP4/HEVC/AAC research | [log](2026-02-26.md) |
| 2026-02-26c | MP4/MOV + MXF implementation | 10 new corruption types, MXF parser, frame map builder, engine refactor | [log](2026-02-26.md) |
| 2026-02-26b | Video corruption research | Deep research: MP4/MOV/MXF structures, glitch art techniques, 7-category taxonomy | [log](2026-02-26.md) |
| 2026-02-26 | Project setup | XcodeGen, MP4 parser, 9 corruption types, full GUI, Directions | [log](2026-02-26.md) |
| 2026-02-18 | Install XcodePreviews globally | Cloned, installed `/preview` command, updated ecosystem docs, tested on Group Alarms | [log](2026-02-18.md) |
| 2026-02-02 | Deploy cookbook + sync commands | Vestige patterns stored, 7 commands added to global CLAUDE.md | [log](2026-02-02.md) |
| 2026-01-29 | Installed Vestige memory MCP server | MCP configured for Claude | [log](2026-01-29.md) |
| 2026-01-24 | LLM failure modes reference | Added 53_llm-failure-modes.md from WFGY analysis | [log](2026-01-24.md) |
| 2026-01-23 | System improvement analysis | Simplified onboarding, consolidated docs, added testing guide | [log](2026-01-23.md) |

---

## Session Log Template

When starting a new session, create a file: `sessions/YYYY-MM-DD-[a|b|c].md`

```markdown
# Session: [Date] [a/b/c]

## Goal
[What we're trying to accomplish]

## Context
- Previous session: [link or summary]
- Current phase: [discovery|planning|implementation|polish|shipping]

## Progress

### Completed
- [x] [What got done]

### In Progress
- [ ] [What's being worked on]

### Discovered
- [New things learned]

### Decisions Made
- [Decision] → logged in decisions.md

### Blockers
- [Anything blocking progress]

## Next Session
- [What to do next]

## Notes
[Anything else worth remembering]
```

---
*One log per session. Link from here.*
