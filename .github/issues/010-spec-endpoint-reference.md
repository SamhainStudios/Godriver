---
title: GTD-010 · SPEC §5 endpoint reference (read-only endpoints)
labels: area/docs, type/spec, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends:
resolution:
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
