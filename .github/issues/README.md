# Issue Backlog (godot-test-driver)

File-based backlog, the source of truth for implementation. Pattern borrowed from the WrongVersion project: briefs live here as numbered files, get seeded to GitHub when work starts, and stay readable without a GitHub login.

## Index

| #   | Brief                                                        | Size | Phase | Depends on | Status |
| --- | ------------------------------------------------------------ | ---- | ----- | ---------- | ------ |
| 000 | Scratch project scaffold + vendored godottpd                 | XS   | 0     |            | DONE   |
| 001 | Spike A1: `/health` served from a running game               | S    | 0     | 000        | DONE   |
| 002 | Spike A2: main-thread dispatcher task queue                  | S    | 0     | 001        | DONE   |
| 003 | Spike A3: StreamPeerTCP thread-safety patch                  | S    | 0     | 001        | DONE   |
| 004 | Spike A4: concurrency + paused-dispatch validation           | S    | 0     | 002, 003   | DONE   |
| 005 | Spike B: one click step end-to-end (incl. headless)          | S    | 0     | 002        | DONE   |
| 006 | Spike C: `test_id` metadata lookup                           | XS   | 0     | 000        | DONE   |
| 007 | Addon self-test scaffold + `.tres` cache-isolation fixture   | S    | 0     | 002        | DONE   |
| 010 | SPEC §5 endpoint reference (read-only endpoints)             | S    | 1     |            |
| 011 | Addon structure + activation flag + `/health`                | S    | 1     | 001–004    |
| 012 | Dispatcher wired into the addon                              | S    | 1     | 011        |
| 013 | `/node/<path>` + property read                               | S    | 1     | 012        |
| 014 | `GET /node?test_id=x` + `GET /nodes?group=y`                 | S    | 1     | 013        |
| 015 | `/scene/current` + `/state` + `/input/map`                   | S    | 1     | 013        |
| 016 | `/reset` (atomic)                                            | S    | 1     | 015        |
| 017 | `@godriver/core` skeleton (fetch wrapper)                    | S    | 1     | 011        |
| 018 | Smoke: Node script queries a running game                    | XS   | 1     | 013–017    |

Phase 2–6 briefs (020+) are written when the phase approaches; the full task breakdown lives in [ROADMAP.md](../../ROADMAP.md).

## Dependency graph

```
000 (scaffold+vendor)
  |
001 (health) ---- 003 (tcp mutex)
  |         \
002 (dispatcher) 006 (test_id)
  |    \           |
  |     004 (concurrency+pause)
  |     007 (self-test scaffold)
  |     005 (e2e click spike)
  |
== Phase 0 exit gate ==
  |
011 (addon+health) -- 010 (SPEC §5) -- 017 (js core)
  |      \
012 (dispatcher) 013 (node) -- 014 (test_id/group) -- 015 (scene/state/inputmap) -- 016 (reset)
  |                                                                    |
  |                              020+ (Phase 2: input & scene — briefs pending)
```

## Rules

- Copy `_TEMPLATE.md` and number the brief in sequence. One brief, one goal; if the goal needs two sentences, split the brief.
- Sizes: **XS** ≤ half day, **S** ≤ 1–2 days. Nothing larger is scheduled.
- Acceptance criteria are observable and testable. "Works correctly" is not a criterion.
- Decided things are stated as facts with their source section (`SPEC §`, `PLAN §`), each with a one-line rationale. Open things name who decides.
- Every brief's front matter has a `resolution:` field — filled with the exact file/section/commit when the work lands.
- `ROADMAP.md` stays the schedule of record; briefs reference phases, they do not restate them.
- Editing: edit the file here, then create/update the GitHub issue manually. No sync-back.
