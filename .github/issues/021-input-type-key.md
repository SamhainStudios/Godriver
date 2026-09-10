---
title: GTD-021 · POST /input/type + POST /input/key — text and action keys
labels: area/addon, area/input, type/feature, priority/P1, size/S
milestone: v0.1
phase: 2
depends: 020
resolution: DONE 2026-09-10 — /input/type + /input/key implemented in addons/godriver/handlers/input_handler.gd (type_text + key + _resolve_key + _make_key); routes wired in api_handler.gd (input_type/input_key share the input_click body-parse case). GdUnit test_input_type_key.gd 6 tests green; FULL SUITE 42/42 exit 0; e2e curl verified (type 200 {chars:2}, key ui_accept 200 {device:16}, unknown key 400 UNKNOWN_KEY, click→label "pressed"). KEY FINDINGS: (1) ClassDB does NOT expose @GlobalScope constants ("Cannot get class @GlobalScope") and Expression cannot resolve global enum constants (self-null error even with base instance) — but a GDScript lambda CAN reference KEY_ENTER directly → generated addons/godriver/handlers/key_map.gd (192 entries, static var MAP, parse-time checked) from core/os/keyboard.h enum Key of the pinned Godot source; C++ members unprefixed (binding adds KEY_), exceptions KEY_0-9/KEY_DELETE already prefixed; KEY_SPECIAL internal (excluded); KEY_CMD_OR_CTRL platform-conditional NOT declared on Windows (excluded). (2) Global key form: press+release flushed SAME frame → is_action_pressed never observable; is_action_just_pressed IS (probe fixture action_probe.gd samples in _process after the dispatcher drain). (3) Typing = targeted path only (grab_focus + per-char unicode events), works headless (LineEdit.text == "hello" verified). (4) GdUnit gotchas: JSON ints as floats (assert_float().is_equal(5.0)); TestDriverServer.setup() returns void. SPEC rev 10 (§5.3 entries + Appendix C); addon-internals.md "Keyboard pipeline (GTD-021)" section. Out of scope confirmed: gamepad/touch/modifier chords (v0.2).
---

# GTD-021 · POST /input/type + POST /input/key — text and action keys

## Context

Clicks (GTD-020) cover pointer interaction. Text entry and action keys complete
the keyboard surface. Global (non-targeted) key events must use the headless
workaround: `Input.parse_input_event()` + `Input.flush_buffered_events()`
(godot#73557 — parse_input_event is a no-op headless without the flush; akien
confirmed the flush delivers events AND updates action state).

## Goal

- `POST /input/type {"path": "...", "text": "hello"}` types text into a focused
  Control (LineEdit/TextEdit) via targeted key events
- `POST /input/key {"key": "ui_accept" | "KEY_ENTER", "action": true}` injects a
  key press/release; action-name form updates Input action state headless

## Scope

**In scope:**

- `/input/type`: resolve target Control, focus it (`grab_focus()`), then per
  character: `InputEventKey` with `unicode` set, pressed + released, via owning
  viewport `push_input(ev, true)`
- `/input/key`: key by name (`KEY_ENTER` → `KEY_ENTER` constant lookup via
  `OS`/`@GlobalScope` class constant map) or by action name (`ui_accept` →
  `InputMap.action_get_events` first key event); global fallback path =
  `Input.parse_input_event` + `Input.flush_buffered_events()`
- Optional `"target"` on /input/key: route through owning viewport instead
- Error codes: 400 MISSING_PARAM, 404 NODE_NOT_FOUND, 400 BAD_TARGET,
  400 UNKNOWN_KEY (name not resolvable), 409 AMBIGUOUS_TEST_ID

**Out of scope:** gamepad (v0.2), touch (v0.2), modifier-chord composition
(shift+letter) — document as limitation.

## Technical specification

- /input/type response: `200 {"injected":true,"chars":<n>,"target":"<path>"}`
- /input/key response: `200 {"injected":true,"key":"<resolved name>","device":16}`
- Device constants per SPEC §6: keyboard = 16 on 4.7+ (DEVICE_ID_KEYBOARD), 0 on 4.3–4.6
- Text typing does NOT go through parse_input_event (needs a focused Control;
  targeted path works headless)

## Acceptance criteria

- [ ] /input/type into a LineEdit sets its `text` property — headless
- [ ] /input/key "ui_accept" fires a Button's `pressed` (focus + action path) — headless
- [ ] /input/key global form updates `Input.is_action_just_pressed` state headless
      (verified via a test node polling action state)
- [ ] Unknown key name → 400 UNKNOWN_KEY; missing params → 400 MISSING_PARAM
- [ ] GdUnit suite green; full suite stays green

## Testing

- [ ] Unit: `test_input_type_key.gd` — LineEdit fixture, Button focus fixture,
      action-state probe node, error codes
- [ ] Live e2e: curl type → /node property read shows text

## Documentation

- [ ] SPEC §5.3 entries filled (rev 9); headless flush workaround documented
- [ ] addon-internals.md: keyboard pipeline section (focus requirement,
      constant-name resolution, flush workaround rationale)

## Files expected to change

```
addons/godriver/handlers/input_handler.gd
addons/godriver/api_handler.gd
scratch/spike/test/unit/test_input_type_key.gd
scratch/spike/test/fixtures/ (LineEdit + action-probe fixtures)
spec/SPEC.md
docs/technical/addon-internals.md
.github/issues/021-input-type-key.md
```

## References

- SPEC §5.3, §6 (flush workaround, device constants)
- godot#73557 (headless parse_input_event no-op)
- ROADMAP Phase 2

## Dependencies

**Blocked by:** [[dep:020]]

**Blocks:** [[dep:022]] [[dep:026]]
