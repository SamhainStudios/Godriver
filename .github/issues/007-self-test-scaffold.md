---
title: GTD-007 · Addon self-test scaffold + .tres cache-isolation fixture
labels: area/addon, type/infrastructure, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 0
depends: 002
resolution: DONE 2026-09-10 — GdUnit4 v5.1.1 vendored at `addons/gdUnit4/` (MIT, tag v5.1.1, commit c924c7a; v6.2.1 evaluated first and REJECTED — does not compile on Godot 4.4, GDScript parse errors in GdUnitTestCIRunner.gd; v5.1.1 README declares 4.3/4.4/4.4.1 support). **UPDATE (2026-09-10, later): project base moved to Godot 4.7.2 — GdUnit4 upgraded to v6.2.1 (tag), which compiles and runs green on 4.7.2 (12/12, exit 0). v5.1.1 remains the 4.4-compatible fallback (backup kept outside repo); see addons/gdUnit4/VENDORED.md.** Headless run verified green: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add scratch/spike/test --ignoreHeadlessMode` → exit 0, 12/12 tests, 0 failures (reports in reports/report_N/). `--ignoreHeadlessMode` is REQUIRED (CLI refuses headless by default, exit 103). Suites: scratch/spike/test/unit/test_dispatcher.gd (submit-from-thread returns main-thread result; main-thread inline — encodes the lambda capture-by-value gotcha: observe callable writes via a Dictionary, not a local), test_serializer.gd (SPEC §4 frozen-shape round-trips: scalars, NaN/Inf as strings, Vector2/3/4+i, Color, Rect2/2i, Quaternion, Basis, Transform2D/3D, AABB, Plane, arrays, dicts, null, non-string keys stringified, Callable unsupported), test_resource_cache_isolation.gd (ported from GUT reference; leak case: in-place .tres mutation survives reload via CACHE_MODE_REUSE; safe case: duplicate(true) mutation does not leak). New fixture: scratch/spike/test/fixtures/mutable_stat_resource.{gd,tres} (class_name MutableStatResource, @export int base_health=100). Findings: (1) JSON.parse_string delivers ints as floats — decode(TYPE_INT) coerces float→int; (2) GdUnit assert_that is type-strict (1.0 != 1) — use assert_float for JSON-fidelity numeric asserts; (3) v5.1.1 float assert lacks is_nan() — use assert_bool(is_nan(x)); (4) gdUnit4's own test resources emit benign UID warnings during --import. Docs: addons/gdUnit4/VENDORED.md written (version choice, update procedure, no deviations); docs/technical/addon-internals.md self-testing section added + stale GTD-003-pending note fixed. CI wiring deferred to GTD-042 per brief.
---

# GTD-007 · Addon self-test scaffold + `.tres` cache-isolation fixture

## Context

The addon must test itself — "who tests the tester" is answered in-repo (PLAN Constraints). The `.tres` cache pollution vector (ResourceLoader `CACHE_MODE_REUSE` persists across scene changes) is documented in SPEC §5.0 and needs a regression fixture from day one.

## Goal

GdUnit4 (or GUT) running headless with the first unit tests: dispatcher queue, serializer round-trip, and the `.tres` cache-isolation fixture.

## Scope

**In scope:**

- Test framework wired into `scratch/spike/` (GdUnit4 preferred; GUT acceptable — decision recorded)
- Dispatcher unit tests (from GTD-002 code)
- §4 Variant serializer round-trip property tests (Vector2/3, Color, NodePath, arrays, dicts, null)
- Port `spec/self-tests/test_resource_cache_isolation.gd` (GUT reference) to the chosen framework; fixture `res://test/fixtures/mutable_stat_resource.tres` (minimal Resource with int `base_health`)

**Out of scope:**

- CI wiring (GTD-042); endpoint tests (Phases 1–2)

## Technical specification

- Cache-isolation contract (SPEC §5.0): mutating a disk-backed `.tres` via a `res://` target leaks through `/reset` (cache not evicted — no public API); `duplicate()`-before-mutation does NOT leak. Both behaviors asserted as documentation-by-test.
- Serializer tests are property-style: serialize → deserialize → compare, across the frozen §4 shape table.

## Acceptance criteria

- [x] Test runner executes headless: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add scratch/spike/test --ignoreHeadlessMode` exits 0
- [x] Dispatcher tests: submit-from-thread returns main-thread result (from GTD-002)
- [x] Serializer round-trip: every §4 shape round-trips byte-equal (semantic equality)
- [x] Cache fixture: leak case asserts mutated value survives `/reset`; safe case asserts `duplicate()` mutation does not leak
- [x] Framework choice + rationale recorded in Resolution

## Testing

- [x] This brief IS the testing infrastructure; its own exit is a green headless run.

## Documentation

- [x] `docs/technical/addon-internals.md` gains a "self-testing" section; SPEC §5.0 cache block cross-references the fixture.

## Files expected to change

```
scratch/spike/tests/**                 # framework + first suites
scratch/spike/test/fixtures/mutable_stat_resource.tres
spec/self-tests/test_resource_cache_isolation.gd   # ported (original kept as reference)
```

## References

- SPEC §4 (shapes), §5.0 (cache out-of-scope block)
- PLAN §Constraints (self-testing strategy), §Sprint 0
- ROADMAP Phase 0

## Dependencies

**Blocked by:** [[dep:002]]

**Blocks:** [[dep:012]] (all later endpoint tasks rely on the scaffold)
