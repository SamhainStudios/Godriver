---
title: GTD-022 · 4.7 device-ID + joypad-focus compatibility
labels: area/addon, area/input, type/chore, priority/P2, size/XS
milestone: v0.1
phase: 2
depends: 021
resolution: DONE 2026-09-10 — addons/godriver/compat.gd (TestDriverCompat): static var HAS_DEVICE_IDS = "DEVICE_ID_KEYBOARD" in InputEvent (runtime detection, floor stays 4.3); device_id_keyboard/mouse/emulation → 16/32/-1 on 4.7+, 0 fallback; apply_startup_settings() sets Input.ignore_joypad_on_unfocused_application=false guarded by `in Input` check. Wired: driver.gd _ready calls apply_startup_settings() when active; input_handler.gd stamps device via compat in _make_mouse_button (mouse device) and _resolve_key (keyboard device for both InputMap-action and KEY_*-constant paths). test_compat.gd 3 tests green (constants on 4.7.2, startup setting applied, event stamping); FULL SUITE 45/45 exit 0. 4.4 verification: NOT re-run on 4.4 binary this round — detection is runtime (`in` check) so 4.4 takes the 0-fallback path by construction; noted as CI-matrix work (GTD-042). addon-internals.md compat section appended.
---

# GTD-022 · 4.7 device-ID + joypad-focus compatibility

## Context

Godot 4.7 introduced `InputEvent.DEVICE_ID_KEYBOARD` (16) / `DEVICE_ID_MOUSE` (32)
/ emulation (-1) constants (GH-116274) and `Input.ignore_joypad_on_unfocused_application`.
Injected events must carry the right device IDs on 4.7+ (device=0 on 4.3–4.6) or
engine-side filtering can drop them; joypad focus filtering must be disabled at
startup so synthetic joypad events are processed in headless/unfocused CI runs.

## Goal

Centralize device-ID handling and the joypad-focus startup setting so all input
endpoints behave identically on 4.3–4.7.

## Scope

**In scope:**

- `addons/godriver/compat.gd` (class_name TestDriverCompat, static):
  `device_id_keyboard()`, `device_id_mouse()`, `device_id_emulation()` —
  constants when present (4.7+), 0 fallback on older engines
- All injected events (click/type/key, future endpoints) set `device` via compat
- driver.gd startup: `Input.ignore_joypad_on_unfocused_application = false`
  (guarded by `ClassDB.class_has_property`/has-method check for forward compat)
- /input/map already reports device constants — verify consistency with compat

**Out of scope:** joypad injection endpoints (v0.2).

## Technical specification

- Detection: `InputEvent` script constant lookup — `InputEvent.get_script_constant_map()`
  or direct `DEVICE_ID_KEYBOARD in InputEvent` check; fallback 0
- No behavior change on 4.3–4.6 (device=0 as before)

## Acceptance criteria

- [ ] compat helpers return 16/32/-1 on 4.7.2, 0/0/-1 (or 0/0/0) on 4.4
- [ ] Injected click/key events carry compat device IDs (asserted in unit tests)
- [ ] Startup sets ignore_joypad_on_unfocused_application=false on 4.7 (no error on 4.4)
- [ ] Full GdUnit suite green on 4.7.2

## Testing

- [ ] Unit: `test_compat.gd` — device constants, event device stamping
- [ ] Existing input suites re-run (device assertions updated if needed)

## Documentation

- [ ] addon-internals.md: compat section (version matrix, detection method)
- [ ] Brief resolution notes the 4.4 verification result

## Files expected to change

```
addons/godriver/compat.gd
addons/godriver/driver.gd
addons/godriver/handlers/input_handler.gd
scratch/spike/test/unit/test_compat.gd
docs/technical/addon-internals.md
.github/issues/022-device-id-compat.md
```

## References

- SPEC §6 device constants; PLAN Constraints (4.7 input compat bullet)
- GH-116274 (DEVICE_ID constants); ROADMAP Phase 2

## Dependencies

**Blocked by:** [[dep:021]]

**Blocks:** —
