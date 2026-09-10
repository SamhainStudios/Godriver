---
title: GTD-014 · GET /node?test_id=x + GET /nodes?group=y
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 013
resolution: DONE 2026-09-10 — GET /node?test_id= + GET /nodes?group= production endpoints, 27/27 GdUnit green + e2e curl verified. Files: addons/godriver/handlers/node_handler.gd (find_by_test_id: whole-tree DFS, 200 {test_id,path} / 404 TEST_ID_NOT_FOUND / 409 AMBIGUOUS_TEST_ID with details.matches per §7; list_group: get_nodes_in_group paginated, meta.total pre-pagination, empty group 200, limit 1..1000 else 400 TYPE_MISMATCH details.expected "1..1000", offset clamped ≥0); addons/godriver/api_handler.gd (routes +"/node"→node_query and "/nodes"→nodes; _extract_args str()s ALL query values — godottpd _extract_query_params auto-converts numerics so test_id=123 would arrive as int; _main_nodes coerces limit/offset defensively from int/float/string). Route collision note: raw-regex ^/node/(?<npath>.+?)[/#?]?$ requires "/node/"+≥1 char so plain "/node" (query form) never collides. Suite scratch/spike/test/unit/test_testid_group_endpoints.gd (3 tests: resolution semantics incl. 400 MISSING_PARAM, numeric test_id stays string, pagination boundaries + empty group 200 + TYPE_MISMATCH + MISSING_PARAM). Findings: (1) GdUnit suite node PERSISTS across tests — fixtures added in before_test accumulate (group total was 9 = 3×3 runs); fixed by queue_free + one process_frame at top of before_test — documented in addon-internals.md. (2) e2e curl: /node?test_id=unknown → 404 TEST_ID_NOT_FOUND; /nodes?group=none → 200 total 0; limit=1001 → 400 TYPE_MISMATCH; /nodes → 400 MISSING_PARAM; /node/root/<path> info route unaffected. SPEC §5.2/§7 verified against implementation; curl examples executed.
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
addons/godriver/handlers/node_handler.gd
```

## References

- SPEC §5.2, §7
- PLAN §Element Identification
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:013]] [[dep:006]]

**Blocks:** [[dep:020]] (input targeting prefers test_id)
