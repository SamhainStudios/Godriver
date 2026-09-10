---
title: GTD-010 · SPEC §5 endpoint reference (read-only endpoints)
labels: area/docs, type/spec, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends:
resolution: DONE 2026-09-10 — SPEC.md rev 7: §5.1 filled (/health with status/godot_version/spec_version; /scene/current with scene resource path + node path; /input/map with InputMap actions + per-type event summaries — key/mouse_button/joypad_button/joypad_motion fields extracted, other types serialize {type} only, device constants per §6); §5.2 filled (shared node-summary shape path/name/type/test_id/child_count/children/script; /node/<path>; /node/<path>/property/<name> with {name,type,value} per §4 and PROPERTY_NOT_FOUND covering engine-private props; /node?test_id= with O(nodes) scan note; /nodes?group= paginated with meta.total, empty group = 200 not 404 per §7, out-of-range limit → 400 TYPE_MISMATCH details.expected "1..1000"); GET /state added to §5.8 (flat values map of script-declared properties, engine built-ins excluded). New Appendix A code MISSING_PARAM (400). /ui/layout contract note preserved as stub (get_global_rect → flat Rect2, offset-transform-aware 4.7+). Phase 2–4 endpoint sections = stubs pointing at implementing briefs. Appendix C rev 7 entry added. All 9 Phase-1 endpoints have schema + status codes + curl.
---

# GTD-010 · SPEC §5 endpoint reference (read-only endpoints)

## Context

SPEC §5 is the last undecided section (v0.1 draft covers §1–§4, §6–§9). Phase 1 implements exactly these endpoints; the reference must exist before (or with) the code so implementation and contract never drift.

## Goal

Every Phase-1 endpoint fully documented in SPEC §5: method, params, response schema, status codes, copy-pasteable `curl`.

## Scope

**In scope:**

- `/health`, `/reset`, `/node/<path>`, `/node/<path>/property/<name>`, `/node?test_id=`, `/nodes?group=`, `/scene/current`, `/state`, `/input/map`
- Each with: request/response JSON examples, status codes (200/400/404/409/504 as applicable), one `curl` per endpoint

**Out of scope:**

- Input/signal/state-write endpoints (documented with their implementing briefs, Phases 2–3)

## Technical specification

- Envelope, error codes, and Variant shapes already frozen (SPEC §2–§4, Appendix A) — §5 only instantiates them.
- Docs principle (PLAN Documentation): every endpoint gets a copy-pasteable `curl` example; examples are executed in CI from GTD-044.

## Acceptance criteria

- [ ] All 9 Phase-1 endpoints documented with schema + status codes + `curl`
- [ ] A stranger could implement a client from SPEC alone (checked against GTD-017/018 implementation)
- [ ] No endpoint response shape contradicts §4 frozen Variant mapping

## Testing

- [ ] Each `curl` example executed against the running addon in the smoke test (GTD-018).

## Documentation

- [ ] SPEC §5 filled; Appendix C rev bumped.

## Files expected to change

```
spec/SPEC.md   # §5 + Appendix C
```

## References

- SPEC §2–§4, Appendix A
- PLAN §SPEC.md Contract Requirements
- ROADMAP Phase 1

## Dependencies

**Blocked by:** —

**Blocks:** [[dep:011]] [[dep:013]] [[dep:015]] [[dep:016]] [[dep:017]]
