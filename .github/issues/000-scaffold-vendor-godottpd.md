---
title: GTD-000 · Scratch project scaffold + vendored godottpd
labels: area/addon, type/spike, priority/P0, agent-ready, size/XS
milestone: v0.1
phase: 0
depends:
resolution: Landed 2026-09-10 — repo root is the dev Godot project (WrongVersion pattern: `project.godot` at root, `.gdignore` in `.github/` + `spec/`); `addons/godottpd/` vendored at pinned commit `dc7b9f45efebc48c3588980926752a7a7d8c5e8d` with `VENDORED.md` (upstream URL, commit, license, update procedure, API-surface observations); upstream MIT license preserved; `--headless --import` exits 0 (second pass; first-pass `!tasks.has(p_task)` noise is the known Godot import race). Local Godot: `C:\Users\bulga\Documents\programacion\godot\Godot_v4.4-stable_win64.exe`.
---

# GTD-000 · Scratch project scaffold + vendored godottpd

## Context

Nothing exists yet. Every Phase 0 spike needs a Godot project to run in and the vendored HTTP server it depends on.

## Goal

A minimal Godot project with `bit-garden/godottpd` vendored, openable headless without errors.

## Scope

**In scope:**

- `scratch/spike/` Godot 4.3+ project (`project.godot`, one main scene with a Button + Label for later spikes)
- `addons/godottpd/` vendored from `bit-garden/godottpd` at a pinned commit, upstream MIT `LICENSE` preserved
- `addons/godottpd/VENDORED.md`: upstream URL, pinned commit, license, update procedure, deviation log (empty initially)

**Out of scope:**

- Any server code (GTD-001)

## Technical specification

- Vendoring policy per PLAN Constraints: review upstream every 2 Godot minors; security fixes ≤30 days; all deviations in `VENDORED.md`.
- Local Godot binary for manual runs: `C:\Users\bulga\Documents\programacion\godot\Godot_v4.4-stable_win64.exe` (CI uses 4.4-stable Linux; matrix 4.3/4.5/4.7 comes in GTD-042).

## Acceptance criteria

- [ ] `godot --headless --path scratch/spike --import` exits 0 with no script errors
- [ ] `addons/godottpd/VENDORED.md` records upstream URL, pinned commit, license
- [ ] Upstream MIT license file preserved inside the vendored tree

## Testing

- [ ] Headless import run (command above) is the test; repeated in CI from GTD-042.

## Documentation

- [ ] `VENDORED.md` created.

## Files expected to change

```
scratch/spike/project.godot          # minimal project
scratch/spike/scenes/main.tscn       # Button + Label fixture scene
addons/godottpd/**                   # vendored server
addons/godottpd/VENDORED.md          # provenance
```

## References

- PLAN §Constraints (vendoring policy), §Open Questions 1
- ROADMAP Phase 0

## Dependencies

**Blocked by:** —

**Blocks:** [[dep:001]] [[dep:006]]
