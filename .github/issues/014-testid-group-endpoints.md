---
title: GTD-014 · GET /node?test_id=x + GET /nodes?group=y
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 013
resolution:
---

# GTD-014 · `GET /node?test_id=x` + `GET /nodes?group=y`

## Context

Spike C (GTD-006) proved metadata lookup; this productionizes it alongside group queries — the two script-free identification mechanisms (PLAN §Element Identification).

## Goal

test_id resolution and group queries as production endpoints with pagination and ambiguity errors.

## Scope

**In scope:**

- `GET /node?test_id=x`: whole-tree scan, 404 on zero, 409 + `matching_paths` on duplicates (SPEC §7)
- `GET /nodes?group=y`: paginated (`limit=100` default, max 1000, `meta.total` — SPEC §5.2)

**Out of scope:**

- Caching/indexing of the scan (revisit only if profiling shows need — open, decides: profiler data from GTD-040)

## Technical specification

- Scan happens on the main thread via the dispatcher (GTD-012); deep trees are the cost concern — pagination bounds response size, not scan cost.

## Acceptance criteria

- [ ] test_id: 200/404/409 semantics exactly per SPEC §7; works with zero scripts
- [ ] Group query: returns matching nodes with paths; `limit`/`meta.total` honored; `limit>1000` → 400
- [ ] Both endpoints self-tested headless

## Testing

- [ ] Self-tests: fixture scene with tagged/duplicate/grouped nodes; pagination boundary cases.

## Documentation

- [ ] SPEC §5 entries verified; `curl` examples executed.

## Files expected to change

```
addons/godot-test-driver/handlers/node_handler.gd
```

## References

- SPEC §5.2, §7
- PLAN §Element Identification
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:013]] [[dep:006]]

**Blocks:** [[dep:020]] (input targeting prefers test_id)
