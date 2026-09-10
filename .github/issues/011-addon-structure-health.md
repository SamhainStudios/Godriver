---
title: GTD-011 · Addon structure + activation flag + /health
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 001, 002, 003, 004
resolution:
---

# GTD-011 · Addon structure + activation flag + `/health`

## Context

Phase 0 proved the mechanics; now they become the real addon structure under `addons/godriver/` (PLAN File Structure), dormant unless flagged.

## Goal

The addon registers as an EditorPlugin + dormant autoload, serves `/health` on activation, and fails loudly on port conflicts.

## Scope

**In scope:**

- `addons/godriver/`: `plugin.cfg`, `plugin.gd`, `http_server.gd`, `api_handler.gd`, vendored `godottpd/` moved in from scratch
- Activation: `--test-driver` in `OS.get_cmdline_user_args()`; dormant otherwise (zero overhead in shipped builds — PLAN Open Q3)
- `/health` → `{status, godot_version, spec_version}` (SPEC §5.1)
- Port: default 9090; taken → clear error; `--test-driver-port=N` override; `=0` → ephemeral, printed to stdout (PLAN Open Q2)
- Binds `127.0.0.1` only; optional `--test-driver-token` (PLAN Open Q4)

**Out of scope:**

- Dispatcher integration (GTD-012), other endpoints

## Technical specification

- EditorPlugin registers the autoload on enable (PLAN Open Q3); autoload checks the flag at `_ready`.
- Port-collision warning prominent: 9090 collides with tugcantopaloglu/godot-mcp and Smalldy/godot-bridge defaults (PLAN Constraints).

## Acceptance criteria

- [ ] Game launched with `--test-driver` serves `/health`; without it, no socket is opened
- [ ] `/health` returns `{"ok":true,"data":{"status":"ok","godot_version":"4.x","spec_version":"0.1"}}`
- [ ] Port taken → startup fails with a clear error naming `--test-driver-port`
- [ ] `--test-driver-port=0` prints the assigned port to stdout
- [ ] Token set → requests without it get 401

## Testing

- [ ] Self-tests: flag gating, health shape, port-conflict error, token rejection (scaffold from GTD-007).

## Documentation

- [ ] SPEC §5.1 finalized; README quickstart draft (activation flags).

## Files expected to change

```
addons/godriver/plugin.cfg
addons/godriver/plugin.gd
addons/godriver/http_server.gd
addons/godriver/api_handler.gd
```

## References

- SPEC §1, §5.1
- PLAN §Open Questions 2–4, §File Structure
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:001]] [[dep:002]] [[dep:003]] [[dep:004]]

**Blocks:** [[dep:012]] [[dep:017]]
