---
title: GTD-024 · GET /assets/loaded — loaded resource inventory
labels: area/addon, area/diagnostics, type/feature, priority/P2, size/S
milestone: v0.1
phase: 2
depends: 015
resolution: DONE 2026-09-10 — DECISION GATE RESOLVED: ResourceLoader.list_handled_resources() does NOT exist on 4.7.2 (verified against the full ClassDB method table — only load/load_threaded_*/has_cached/get_cached_ref/exists/list_directory etc.). Fallback implemented per SPEC §5.9a: addons/godriver/handlers/assets_handler.gd (TestDriverAssetsHandler) — engine-wide resource COUNT via Performance.get_monitor(OBJECT_RESOURCE_COUNT) + DRIVER-TRACKED inventory (static _tracked array; scene_handler tracks successful /scene/load → source "scene_load" and /reset → source "reset"), paginated limit 1..1000 (400 TYPE_MISMATCH outside) / offset with meta.total; empty = 200. Wired: scene_handler.load_scene + reset call TestDriverAssetsHandler.track after done; api_handler route "/assets/loaded" get → assets_loaded (shares the nodes _extract_args case for limit/offset). test_assets_loaded.gd 2 tests green (shape + tracked inventory grows after load; pagination limit=1 + TYPE_MISMATCH); FULL SUITE 50/50 exit 0. e2e curl verified (after load: {count:22, meta:{total:1}, resources:[{path:alt_scene.tscn, source:scene_load}]}). Gotcha reused: helper must not be named _get (Object virtual collision) → _http_get. SPEC rev 12 (§5.9a new section documenting the scope limitation).
---

# GTD-024 · GET /assets/loaded — loaded resource inventory

## Context

Tests need to observe what the game has loaded (leak detection, load-state
assertions). SPEC §5 defines a read-only inventory endpoint. Godot exposes
loaded resources indirectly; the practical source is the ResourceLoader cache
via `ResourceLoader.list_handled_resources()` (4.3+) — verify availability and
shape on 4.7.2 before committing to the response shape.

## Goal

`GET /assets/loaded` returns the list of loaded resources with path, type, and
estimated memory.

## Scope

**In scope:**

- `handlers/asset_handler.gd` (TestDriverAssetHandler): enumerate loaded
  resources — path, type (`get_class()`), and vram estimate where available
  (RenderingServer.get_resource_info for textures if accessible; otherwise omit
  field and document)
- Response: `200 {"resources":[{path,type,vram?}...],"count":<n>}` — paginated
  with limit/offset like /nodes (limit default 100, max 1000, meta.total)
- Error codes: 400 TYPE_MISMATCH (bad limit)

**Out of scope:** per-resource content inspection; cache eviction (no public API —
§5.0 resource-cache block).

## Technical specification

- PRIMARY: `ResourceLoader.list_handled_resources()` — verify it exists on 4.7.2
  and returns RIDs or paths; map RID → path via ResourceLoader.get_resource_path
  if needed. If the API proves unusable, fall back to tracking resources the
  addon observes (document the limitation in SPEC) — decision gate recorded in
  resolution.
- All enumeration on main thread via dispatcher funnel (sync handler)

## Acceptance criteria

- [ ] After loading a known .tres fixture, it appears in the list with correct type
- [ ] Pagination works (limit/offset/meta.total); bad limit → 400 TYPE_MISMATCH
- [ ] Empty game state → 200 with empty list (not 404)
- [ ] GdUnit suite green; full suite stays green

## Testing

- [ ] Unit: `test_assets_loaded.gd` — fixture load visible, pagination, errors
- [ ] Live e2e: curl /assets/loaded

## Documentation

- [ ] SPEC §5 entry filled (rev 9) with enumeration-source note
- [ ] addon-internals.md: asset enumeration section (API choice + fallback)

## Files expected to change

```
addons/godriver/handlers/asset_handler.gd
addons/godriver/api_handler.gd
scratch/spike/test/unit/test_assets_loaded.gd
spec/SPEC.md
docs/technical/addon-internals.md
.github/issues/024-assets-loaded.md
```

## References

- SPEC §5 (assets entry), §5.0 (resource-cache block)
- ROADMAP Phase 2

## Dependencies

**Blocked by:** [[dep:015]]

**Blocks:** —
