---
title: GTD-011 · Addon structure + activation flag + /health
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 001, 002, 003, 004
resolution: DONE 2026-09-10 — addons/godriver/ (plugin name "Godriver", Samhain Studios v0.1.0): plugin.cfg + plugin.gd (EditorPlugin, _enter_tree registers autoload Godriver="*res://addons/godriver/driver.gd"; Godot 4 has no remove_autoload_singleton — manual removal documented), driver.gd (autoload entry; static parse_args(args)->{port,token} unit-testable — default 9090, --test-driver-port=N, 0=ephemeral prints GODRIVER_PORT=<n>, --test-driver-token; dormant without --test-driver; PROCESS_MODE_ALWAYS; headless root-size fix; start() false → push_error naming --test-driver-port + quit(1)), http_server.gd (class_name TestDriverServer; setup(port,token); wraps HttpServer.new(true) bind 127.0.0.1; start()->bool checks _http._server.is_listening() because godottpd swallows listen errors (err 22 → _print_debug + stop()); bound_port = TCPServer.get_local_port()), api_handler.gd (class_name TestDriverApi; SPEC_VERSION "0.1"; _authorized scans headers case-insensitively for Authorization == "Bearer <token>" — godottpd stores headers verbatim mixed-case; empty configured token = auth disabled; handle_health → SPEC §5.1 shape {status:"ok", godot_version, spec_version} or 401 UNAUTHORIZED envelope). project.godot: autoload Godriver added; config/name="godriver-dev". SPIKE GATE RENAMED: spike_server.gd now gates on "--spike" (was --test-driver) so spike and addon never both bind 9090; spike self-tests run as `-- --spike --self-test[-aN|-b|-c]`. GdUnit suite scratch/spike/test/unit/test_addon_server.gd (5 tests) → full suite 17/17 green exit 0. End-to-end verified: `-- --test-driver` → [godriver] listening on 127.0.0.1:9090; curl /health → 200 exact envelope; with --test-driver-token=s3cret → no/wrong token 401 UNAUTHORIZED, right token 200. Debugging findings: (1) GdUnit auto_free() returns Variant — explicit typing required under 4.7 warnings-as-errors (`var s: TestDriverServer = auto_free(...)`); (2) "--test-driver-port=7777".get_slice("=", 1) — value is index 1, not 2; (3) stale .godot/global_script_class_cache.cfg after the godot-test-driver→godriver rename — delete + re-import; (4) GdUnit v6.2.1 scene_runner has NO simulate_start() — dormancy test uses plain add_child + child-count assert. Docs: docs/technical/addon-internals.md gained "Addon structure (GTD-011)" section + test_addon_server suite entry + --spike run pattern.
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
