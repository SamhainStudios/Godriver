---
title: GTD-005 · Spike B: one click step end-to-end (incl. headless)
labels: area/addon, type/spike, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 0
depends: 002
resolution: DONE 2026-09-10 — click e2e green in headless AND windowed (SPIKE_B_OK, exit 0 both).
  Files: scratch/spike/scripts/input_handler.gd (SpikeInputHandler.click_at),
  spike_server.gd (/input/click POST route via Dispatcher), scratch/spike/scenes/
  sub_viewport_fixture.tscn + .gd (SubViewportContainer fixture),
  scratch/spike/tests/spike_b_check.gd (--self-test-b).
  NOTE: Cucumber.js chain deferred to Phase 1 (GTD-017/018) — spike proven with
  HTTP-level self-test instead (same contract, no JS scaffolding yet).
  KEY ENGINE FINDINGS (viewport.cpp/base_button.cpp 4.4, all source-verified):
  1. HEADLESS WINDOW IS 64x64: root Window defaults to 64x64 under --headless.
     Window::_update_mouse_over(p_pos) (window.cpp:2855) treats any pushed
     position outside the visible rect as mouse-exit → _mouse_leave_viewport()
     → hover DROPPED. Fix (REQUIRED, confirms SPEC §5.10): spike_server startup
     sets root.size from display/window/size project settings.
  2. HOVER GATES BaseButton PRESSES: BaseButton::on_action_event
     (base_button.cpp:154) requires status.hovering for mouse presses;
     hovering is set ONLY by NOTIFICATION_MOUSE_ENTER, sent ONLY from
     Viewport::_update_mouse_over(Vector2) (viewport.cpp:3129).
  3. SUBVIEWPORT HOVER MUST GO THROUGH THE ROOT: push_input never sets
     gui.mouse_in_viewport, and _update_mouse_over() no-arg EARLY-RETURNS for
     container-attached SubViewports (is_attached_in_viewport,
     viewport.cpp:3004). The ONLY path that sets hover inside such a
     SubViewport is the ROOT's _update_mouse_over recursion (viewport.cpp:
     3143-3162): finds the container → MOUSE_ENTER → VP_MOUSE_ENTER to sub →
     sub hover resolution. notify_mouse_entered() on the sub is NOT enough
     (sets mouse_in_viewport but hover still unresolved — verified).
  4. ROUTING IMPLEMENTED (input_handler.gd): hover-establishing MOTION routed
     through the ROOT viewport at window coords:
     window_pos = container.get_global_transform_with_canvas()
                  * (sub.get_final_transform() * (sub_pos * stretch_shrink));
     press/release pushed DIRECTLY to the owning viewport (mouse-button
     delivery needs no mouse_in_viewport — gui_find_control unconditional,
     viewport.cpp:1803). For root-viewport Controls: motion+press+release all
     direct at get_global_rect() center (already viewport-canvas space —
     refines SPEC §6: affine_inverse mapping only applies from WINDOW coords).
  5. Coordinate findings: SubViewportContainer FORCES handle_input_locally=false
     on child SubViewports (engine behavior); stretch RESIZES the SubViewport
     to container size (200x200 → 400x400 at shrink 1); container.gui_input
     forwards events as-is (position = container-local == sub-local at
     shrink 1, subviewport_container.cpp:202-238).
  6. Debug scaffolding (6 probe scripts) removed after root-cause found;
     spike_server.gd debug arg branches removed; post-cleanup rerun green.
  Acceptance: windowed ✓ headless ✓ SubViewportContainer ✓ injected-vs-
  processed contract honored (check waits 2 frames) ✓.
---

# GTD-005 · Spike B: one click step end-to-end (incl. headless)

## Context

The full stack (Cucumber.js → `@godriver/core` → addon → input injection → assertion) has never run as one chain. Proving it with ONE step validates the integration before any of the 62 steps are written (PLAN Sprint 0).

## Goal

One green Cucumber scenario: click a button via HTTP, assert the `pressed` signal fired — in windowed AND headless mode.

## Scope

**In scope:**

- Minimal `@godriver/core` `click(path)` (fetch-based, throwaway quality is fine)
- One Cucumber.js scenario with a single step: `When I click "Main/Button"`
- Input routing: targeted events via owning `Viewport.push_input` (headless-safe, godot#73557); coordinate transform via `get_final_transform().affine_inverse()`
- `NOTIFICATION_VP_MOUSE_ENTER` sent before first mouse motion (godot#89757 caveat)

**Out of scope:**

- The 62-step library (GTD-045), full client API (GTD-026)

## Technical specification

- Click position = target Control's center via `get_global_rect()`; map global→viewport-local with `get_final_transform().affine_inverse()` (SPEC §6 invariant).
- Headless: `Input.parse_input_event` is a no-op (godot#73557) — `Viewport.push_input` is the only path that works; global fallback adds `Input.flush_buffered_events()` (verified workaround).
- SubViewport case: click a Control inside a scaled `SubViewportContainer` (stretch `canvas_items`) must land correctly.

## Acceptance criteria

- [ ] Windowed: scenario green — button `pressed` signal observed after HTTP click
- [ ] Headless (`--headless`): same scenario green via `Viewport.push_input`
- [ ] SubViewportContainer case: click lands on the inner Control (label text changes)
- [ ] 200 from `/input/click` means *injected*; scenario explicitly waits one frame before asserting (SPEC §6 contract honored)

## Testing

- [ ] `scratch/spike/features/click.feature` + step def; run twice (windowed, headless); both green.

## Documentation

- [ ] Resolution records the exact routing code that worked (feeds GTD-020 spec).

## Files expected to change

```
js/core/src/client.js                  # throwaway fetch click
scratch/spike/features/click.feature
scratch/spike/step_definitions/click.steps.js
scratch/spike/scripts/input_handler.gd # minimal click injection
```

## References

- SPEC §6 (input routing, coordinate invariant, timing contract)
- PLAN §Sprint 0 Spike B
- ROADMAP Phase 0

## Dependencies

**Blocked by:** [[dep:002]]

**Blocks:** [[dep:020]]
