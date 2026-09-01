# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] [Task description]

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

- [x] Task 0.1: Add the macOS unit-test target and shared scheme
- [x] Task 0.2: Add checked binary arithmetic and byte spans
- [x] Task 0.3: Add throwing checked data access
- [x] Task 0.4: Freeze corpus schema v1 models
- [x] Task 0.5: Add canonical manifest encoding and validation
- [x] Task 0.6: Add fixture-keyed seed derivation
- [x] Task 1.1: Implement strict BER decoding metadata
- [x] Task 1.2: Implement bounded diagnostic KLV inspection
- [x] Task 1.3: Add streaming file I/O and SHA-256
- [x] Task 1.4: Implement mutation recording and exact-diff verification
- [x] Task 1.5: Implement atomic staging and generator shell

---

## Progress Calculation

```
Sprint Progress = checked in Current Sprint / total in Current Sprint
Overall Progress = (archived count + checked) / (backlog + current + archived)
```

Archived task count is read from `tasks-archive.md` header.

## Workflow Integration

| Command | Action |
|---------|--------|
| `/interview` | Adds tasks to Backlog |
| `/plan` | Moves Backlog → Current Sprint |
| `/execute` | Checks off tasks as waves complete |
| `/log` | Archives checked tasks, updates PROJECT_STATE.md progress bar |
| `/status` | Reports progress from checkbox counts |

---
*Location: `docs/TASKS.md`. Parsed by Directions app.*
