---
title: GTD-020 · POST /input/click — targeted mouse injection
labels: area/addon, area/input, type/feature, priority/P1, size/S
milestone: v0.1
phase: 2
depends: 014
resolution: DONE 2026-09-10 — TestDriverInputHandler.click(tree, args) + resolve_target (path XOR test_id; reuses _scan_test_id raw); api_handler route "/input/click" post→input_click with worker-thread body parse (get_body_parsed + JSON fallback); BAD_TARGET for non-Controls. Suite test_input_click.gd 4/4 green; full suite 37/37 green exit 0; e2e curl verified (click → label "pressed", 404 NODE_NOT_FOUND). Findings: (1) headless root Window is 64x64 — driver.gd fixes root.size at startup but the dormant GdUnit autoload does not, so the test sets root.size from project settings in before_test (button center outside the rect = mouse-exit = hover dropped = press ignored); (2) auto-named inner Control needed an explicit name for path lookup; (3) PowerShell curl --data-binary needs plain double quotes inside single quotes (\" passes literally). SPEC rev 9 (§5.3 /input/click filled, coordinate invariant refined); addon-internals.md input-injection section added.
---

# GTD-020 · POST /input/click — targeted mouse injection

## Context

Spike B (GTD-005) proved the full click pipeline headless and windowed, including
SubViewportContainer-embedded controls. The working implementation lives in
`scratch/spike/scripts/input_handler.gd` (SpikeInputHandler) and must graduate into
the addon. SPEC §5.3 and §6 define the contract; SPEC §6 defines the timing
contract (200 = injected only; auto-wait is client-side).

## Goal

`POST /input/click {"path": "/root/Main/Button"}` (or `{"test_id": "..."}`) injects
a hover-establishing motion + press + release into the target's owning viewport;
the Button's `pressed` signal fires.

## Scope

**In scope:**

- Graduate spike input routing into `addons/godriver/handlers/input_handler.gd`
  (TestDriverInputHandler gains `click_at(tree, path)`; keep `input_map()`)
- Target resolution: node path OR `test_id` (reuse GTD-014 lookup; 404/409 codes)
- Routing rules (SPEC §6, spike-verified):
  - Root-viewport Controls: motion + press + release direct to owning viewport
    `push_input(ev, true)`; coords = `get_global_rect()` center (viewport-canvas)
  - SubViewportContainer-embedded: hover motion through ROOT viewport at window
    coords (`container.get_global_transform_with_canvas() * (sub.get_final_transform() * (sub_pos * stretch_shrink))`);
    press/release direct to owning viewport
  - Standalone SubViewport: `notify_mouse_entered()` before motion
- `POST /input/click` route in api_handler (sync funnel — no coroutine needed)
- Error codes: 400 MISSING_PARAM, 404 NODE_NOT_FOUND / TEST_ID_NOT_FOUND,
  409 AMBIGUOUS_TEST_ID, 400 BAD_TARGET (target is not a Control)

**Out of scope:** `/input/type`, `/input/key` (GTD-021); drag (v0.2); touch (v0.2).

## Technical specification

- Body: `{"path": "..."} | {"test_id": "..."}` — exactly one required
- Response: `200 {"ok":true,"data":{"injected":true,"target":"<path>","viewport":"<vp path>"}}`
- Events: `InputEventMouseMotion` (hover) → `InputEventMouseButton` pressed →
  released, `button_index = MOUSE_BUTTON_LEFT`, `device` per §6 (MOUSE=32 on 4.7)
- All node-touching work inside `dispatcher.submit` (main thread)

## Acceptance criteria

- [ ] Click on root-viewport Button fires `pressed` (label changes) — headless AND windowed
- [ ] Click on SubViewportContainer-embedded Button fires `pressed` — headless
- [ ] `test_id` targeting works; ambiguity → 409 with `details.matches`
- [ ] Non-Control target → 400 BAD_TARGET; missing node → 404
- [ ] GdUnit suite green; full suite stays green

## Testing

- [ ] Unit: `test_input_click.gd` — root click, subviewport click, test_id click,
      error codes (reuse spike fixture scenes)
- [ ] Live e2e: curl click → label text changes (verify via /node property read)

## Documentation

- [ ] SPEC §5.3 `/input/click` entry filled (rev 9)
- [ ] `docs/technical/addon-internals.md`: input-injection pipeline section
      (routing rules table, coordinate invariants, hover-gate findings)

## Files expected to change

```
addons/godriver/handlers/input_handler.gd
addons/godriver/api_handler.gd
scratch/spike/test/unit/test_input_click.gd
spec/SPEC.md
docs/technical/addon-internals.md
.github/issues/020-input-click.md
```

## References

- SPEC §5.3, §6 (timing + routing contract)
- Spike B findings (GTD-005 resolution)
- ROADMAP Phase 2

## Dependencies

**Blocked by:** [[dep:014]]

**Blocks:** [[dep:021]] [[dep:026]]
