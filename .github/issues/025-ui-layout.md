---
title: GTD-025 · GET /ui/layout/<path> — Control layout inspection
labels: area/addon, area/ui, type/feature, priority/P1, size/S
milestone: v0.1
phase: 2
depends: 013
resolution: DONE 2026-09-10 — addons/godriver/handlers/ui_handler.gd (TestDriverUiHandler): layout() snapshot {path,type,visible,visible_in_tree,global_rect:{x,y,w,h} via get_global_rect() (viewport-canvas coords, GTD-005 invariant), position,size,anchors:{anchor_*/offset_* flat floats},pivot,rotation,scale,mouse_filter} + ?depth=N recursion (MAX_DEPTH 16, 400 TYPE_MISMATCH outside 0..16); get_layout reuses TestDriverInputHandler.resolve_target (path XOR test_id → 404 TEST_ID_NOT_FOUND/409 AMBIGUOUS_TEST_ID). api_handler: plain "/ui/layout" (test_id query) + raw-regex "^/ui/layout/(?<npath>.+?)[/#?]?$" both → ui_layout; _extract_args reads npath group + test_id + depth; _main_ui_layout maps npath → path arg. test_ui_layout.gd 3 tests green (rect matches editor-set rect; depth=1 includes child layout with correct global coords, depth 0 omits children; test_id query; 404/400 BAD_TARGET/TEST_ID_NOT_FOUND). FULL SUITE 53/53 exit 0. e2e curl verified (/ui/layout/root/Main/Button?depth=1 → full snapshot). Bug fixed during dev: recursive layout() returns the data dict directly (not funnel shape). SPEC rev 13 (§5.1 /ui/layout entry filled); addon-internals.md layout section.
---

# GTD-025 · GET /ui/layout/<path> — Control layout inspection

## Context

UI tests need geometry: is the button where it should be, visible, correctly
sized? SPEC §5.1 defines the layout contract: bounds via `get_global_rect()`
(flat Rect2 {x,y,w,h} per §4), offset-transform-aware on 4.7+
(`Control.offset_transform_*`). GTD-013's node summary covers identity; this
covers geometry.

## Goal

`GET /ui/layout/<path>` returns a Control's layout snapshot: bounds, position,
size, visibility, anchors, and (recursively, optional) children layout.

## Scope

**In scope:**

- `handlers/ui_handler.gd` (TestDriverUiHandler): layout(node) for a single
  Control — `{path, type, visible, visible_in_tree, global_rect:{x,y,w,h},
  position, size, anchors:{left,top,right,bottom,offset_*}, pivot, rotation,
  scale, mouse_filter}` (§4-serialized)
- `?depth=N` (default 0): include children layouts recursively up to depth
- Error codes: 404 NODE_NOT_FOUND, 400 BAD_TARGET (not a Control), 400 BAD_PATH
- test_id targeting: `GET /ui/layout?test_id=` (reuse GTD-014 lookup)

**Out of scope:** theme inspection; font metrics; 3D layout (/ui/layout3d is
deferred v0.2+).

## Technical specification

- bounds = `get_global_rect()` (viewport-canvas coords — GTD-005 invariant);
  on 4.7+ note offset-transform awareness in docs (get_global_rect already
  accounts for it per engine source)
- visible_in_tree = `is_visible_in_tree()`; anchors via `anchor_*` /
  `offset_*` properties (flat floats per §4)

## Acceptance criteria

- [ ] Layout of a positioned Button matches its editor-set rect (headless)
- [ ] ?depth=1 includes child layouts; depth 0 does not
- [ ] Non-Control → 400 BAD_TARGET; missing → 404; test_id query works
- [ ] GdUnit suite green; full suite stays green

## Testing

- [ ] Unit: `test_ui_layout.gd` — rect values, depth recursion, error codes
- [ ] Live e2e: curl /ui/layout/root/Main/Button

## Documentation

- [ ] SPEC §5.1 /ui/layout entry filled (rev 9)
- [ ] addon-internals.md: layout section (coordinate space note)

## Files expected to change

```
addons/godriver/handlers/ui_handler.gd
addons/godriver/api_handler.gd
scratch/spike/test/unit/test_ui_layout.gd
spec/SPEC.md
docs/technical/addon-internals.md
.github/issues/025-ui-layout.md
```

## References

- SPEC §5.1, §4 (Rect2 shape), §6 (coordinate invariants)
- ROADMAP Phase 2

## Dependencies

**Blocked by:** [[dep:013]]

**Blocks:** [[dep:026]]
