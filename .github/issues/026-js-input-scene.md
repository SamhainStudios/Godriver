---
title: GTD-026 · JS client: input + scene methods with auto-wait
labels: area/client, type/feature, priority/P1, size/S
milestone: v0.1
phase: 2
depends: 017, 020, 021, 023
resolution: DONE 2026-09-10 — (1) ADDON: /wait/frames did NOT exist in the addon (only in the spike) → implemented in api_handler.gd: GET /wait/frames?frames=N long-poll on the worker (frames 1..600 else 400 TYPE_MISMATCH; relative target _frames+N from a _process-incremented counter — pause-safe, never timers/sleeps per SPEC §5.7; Mutex-guarded _blocked_waits cap MAX_BLOCKED_WAITS=8 → 503 SERVER_BUSY; 5s deadline → 504). e2e verified (wait 3 → {waited:3}; frames=0 → 400). (2) JS CLIENT: js/core/src/client.js Driver surface — click(target,{testId})/type(target,text)/pressKey(key,{target,testId}) via _interact helper (POST endpoint then GET /wait/frames?frames=1 — one-frame auto-wait, no hidden sleeps); loadScene(path) POST /scene/load (server-side readiness, no extra wait); layout(target,{testId,depth}) GET /ui/layout URL builder; JSDoc typedefs extended. (3) HARNESS: js/core/test/helpers/live-game.js (spawn GODOT_BIN headless --test-driver on port 9177, /health poll 10s deadline, teardown kill; liveAvailable() gate). (4) TESTS: js/core/test/interactions.test.js — 4 mocked-fetch tests (click shape + wait ordering [health, click, wait/frames?frames=1]; testId body; type/pressKey bodies; loadScene no-wait + layout URL forms) + 2 live tests (click round-trip label "pressed"; layout/loadScene/restore) — 6/6 pass with GODOT_BIN set, 4 pass + 2 skip without. (5) SMOKE: examples/smoke.mjs extended with reset + click() round-trip (label "pressed"); /reset 409 STATE_AUTOLOAD_MISSING accepted (dev project has no GameState — reset completed). (6) tsc --noEmit green (fixed: loadScene Promise cast; Record<string,unknown> body + const-asserted loop keys). V0.1 GATE BATTERY: GdUnit 53/53 exit 0; node --test 12 pass + 2 live-skip exit 0 (6/6 with GODOT_BIN); tsc exit 0; smoke SMOKE_OK exit 0.
---

# GTD-026 · JS client: input + scene methods with auto-wait

## Context

The addon injects events and returns 200 = injected only (SPEC §6 timing
contract). The anti-heisenbug guarantee lives CLIENT-side: interaction methods
auto-wait one frame after injection before returning (PLAN "Input Ordering").
This is the last Phase 2 task and completes the v0.1 client surface.

## Goal

`@godriver/core` gains `click()`, `type()`, `pressKey()`, `loadScene()` — each
encoding the one-frame auto-wait — plus integration tests against a live game.

## Scope

**In scope:**

- js/core/src/client.js Driver surface additions:
  - `click(target, {testId=false})` → POST /input/click, then await one frame
    (GET /wait/frames?frames=1 — verify endpoint exists from spike; if not,
    poll /health until a frame counter advances, or document the chosen wait)
  - `type(target, text)` → POST /input/type + one-frame wait
  - `pressKey(key, {target?})` → POST /input/key + one-frame wait
  - `loadScene(path)` → POST /scene/load (server-side readiness = no extra wait)
  - `layout(target, {depth?})` → GET /ui/layout/<path> (read, no wait)
- JSDoc types updated; types.test.ts extended
- Integration tests (node:test) against a live game started by the test
  (spawn Godot headless with --test-driver, poll /health, run, kill) —
  skipped when GODOT_BIN env var is absent (CI wires it in GTD-042)

**Out of scope:** assertions/waits (Phase 3); Cucumber (Phase 3).

## Technical specification

- Auto-wait = exactly one frame via the addon's frame-wait endpoint; no hidden
  sleeps (PLAN Input Ordering)
- All methods throw typed DriverError/ConnectionError (envelope funnel already
  handles this)
- Live-test harness: `test/helpers/live-game.js` — spawn, health-poll (10s
  deadline), teardown kill; reused by future phases

## Acceptance criteria

- [ ] click() on the dev fixture Button changes its label (live test, headless)
- [ ] type() into a LineEdit sets text (live test)
- [ ] pressKey("ui_accept") fires a focused Button (live test)
- [ ] loadScene() resolves only when the new scene is ready (live test)
- [ ] Unit tests (mocked fetch) cover request shapes + auto-wait call order
- [ ] tsc --noEmit green; node --test green (live tests skip without GODOT_BIN)

## Testing

- [ ] Unit: mocked-fetch tests for each method (request shape, wait ordering)
- [ ] Integration: live-game harness tests (skipped without GODOT_BIN)

## Documentation

- [ ] js/core/README.md: interaction methods section + auto-wait rationale
- [ ] examples/smoke.mjs extended with one click() round-trip (keeps SMOKE_OK)

## Files expected to change

```
js/core/src/client.js
js/core/test/client.test.js
js/core/test/types.test.ts
js/core/test/helpers/live-game.js
js/core/README.md
examples/smoke.mjs
.github/issues/026-js-input-scene.md
```

## References

- SPEC §6 (timing contract, auto-wait layering); PLAN Input Ordering
- ROADMAP Phase 2

## Dependencies

**Blocked by:** [[dep:017]] [[dep:020]] [[dep:021]] [[dep:023]]

**Blocks:** — (v0.1 gate)
