---
title: GTD-006 · Spike C: test_id metadata lookup
labels: area/addon, type/spike, priority/P0, agent-ready, size/XS
milestone: v0.1
phase: 0
depends: 000
resolution: 2026-09-10 — DONE. SPIKE_C_OK exit 0 (headless). Files: scratch/spike/scripts/test_id_lookup.gd (SpikeTestIdLookup.find_all, static depth-first scan of get_tree().root — whole-tree scope, not just current_scene, because spike fixtures are siblings of the main scene), scratch/spike/scripts/test_id_fixture.gd (code-built fixture: Tagged unique / DupA+DupB duplicate pair / Untagged), scratch/spike/tests/spike_c_check.gd (--self-test-c: 200+path, 404 NODE_NOT_FOUND, 409 AMBIGUOUS_MATCH with details.matching_paths, node-name≠test_id sanity). Route: GET /node?test_id= in spike_server.gd _handle_node (marshaled through Dispatcher). Findings: (1) godottpd parses query strings at header-parse time (http_server.gd:196) and its _to_string debug log OMITS the query field — don't trust the request log for query debugging; (2) router regex ^/node[/#?]?$ matches request.path AFTER query split, so query params work fine on plain paths; (3) scan cost note for GTD-014: full-tree DFS with has_meta+str compare is O(nodes); fine at spike scale, pagination/caching decision deferred to GTD-014 as planned. Envelope gotcha: data fields live under body.data, error under body.error — check scripts must read the right nesting.
---

# GTD-006 · Spike C: test_id metadata lookup

## Context

`test_id` via node metadata is the primary element-identification mechanism (PLAN §Element Identification) — it must resolve without scripts and fail loudly on ambiguity.

## Goal

`GET /node?test_id=x` resolves a node with Inspector-set metadata; zero matches → 404; duplicates → 409 with matching paths.

## Scope

**In scope:**

- Recursive metadata scan of the current scene for `test_id`
- Error semantics per SPEC §7 (error-on-ambiguity, not first-match)

**Out of scope:**

- Group queries (GTD-014), productionization (GTD-014)

## Technical specification

- Scan: depth-first over `current_scene`, `node.get_meta("test_id")`; whole-tree scope per SPEC §7.
- Rationale for error-on-ambiguity: silent first-match hides broken test suites; 409 with the matching path list makes the failure actionable.

## Acceptance criteria

- [ ] Node with Inspector metadata `test_id = "start_button"` resolves; response includes its path
- [ ] Unknown `test_id` → 404 with envelope error
- [ ] Two nodes sharing a `test_id` → 409 with `details.matching_paths` array
- [ ] Works with zero scripts on any node

## Testing

- [ ] `scratch/spike/tests/spike_c_check.gd`: fixture scene with 3 nodes (one tagged, one duplicate pair); asserts 200/404/409; prints SPIKE_C_OK.

## Documentation

- [ ] Resolution notes scan cost on deep trees (feeds GTD-014 pagination decision).

## Files expected to change

```
scratch/spike/scripts/test_id_lookup.gd
scratch/spike/tests/spike_c_check.gd
scratch/spike/scenes/test_ids.tscn
```

## References

- SPEC §7 (test_id resolution rules)
- PLAN §Element Identification, §Sprint 0 Spike C
- ROADMAP Phase 0

## Dependencies

**Blocked by:** [[dep:000]]

**Blocks:** [[dep:014]]
