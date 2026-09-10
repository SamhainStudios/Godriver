---
title: GTD-017 · @godriver/core skeleton (fetch wrapper)
labels: area/client, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 011
resolution: DONE 2026-09-10 — @godriver/core skeleton landed, 8/8 node:test green + tsc --noEmit green + live-game e2e verified. Files: js/package.json (npm workspaces root, "type":"module", typecheck script), js/core/package.json (@godriver/core 0.1.0, ES modules, engines node>=18, deps: undici only — zero test-runner deps), js/core/src/client.js (connect(port, {host, token, timeoutMs=5000, maxSockets=16}) verifies /health before returning; _request unwraps {ok,data}/{ok,error} envelope; DriverError carries code/message/status/details; ConnectionError for refused/timeout (TimeoutError/AbortError name check); bearer token header; POST JSON body + content-type; undici Agent pool sized explicitly — SPEC §6.1), js/core/test/client.test.js (8 tests, node:test built-in, per-path fetch mock router), js/core/test/types.test.ts (tsc --noEmit type-test), js/core/README.md (install/connect/options/error model/pool sizing). Findings: (1) undici Agent option is `connections` not `maxSockets`; undici is a runtime dep (Node doesn't expose its internal undici as importable) — allowed, it is not a test-runner dep; (2) type-test must be .ts not .d.ts (ambient-context restrictions); devDeps typescript + @types/node added at js/ root; (3) mock-fetch tests must route per-path — connect() calls /health first, so mocks that fail /health kill connect() before the assertion (scope failures to the target path); (4) mock.method() returns the mock function itself (not destructurable); calls[0] is connect's /health, target request is calls[1]; (5) invalid syntax: optional chain after `new` expression. E2E (live --test-driver game): health 200 exact shape, /node/root/Main summary, /node/root/Nope → DriverError NODE_NOT_FOUND 404, connect(9099) → ConnectionError.
---

# GTD-017 · `@godriver/core` skeleton (fetch wrapper)

## Context

`@godriver/core` is the portable contract — zero runner deps, the only package language ports reimplement (PLAN Monorepo). Type safety comes from JSDoc + generated `.d.ts`, no TS build step.

## Goal

`js/core` npm package: `connect(port)` + typed request/response layer over the SPEC envelope.

## Scope

**In scope:**

- npm workspaces root (`js/package.json`), `js/core` package (`"type": "module"`)
- `client.js`: fetch wrapper, envelope unwrapping, error mapping (code/message/details → typed errors), timeout (default 5s)
- `connect(port)`: verifies `/health`, returns driver handle
- HTTP agent sizing: `maxSockets ≥ max_blocked_waits` (SPEC §6.1) — set explicitly, not defaulted
- JSDoc types + `tsc --noEmit` type-test file in CI

**Out of scope:**

- Endpoint methods beyond health (GTD-018+), Cucumber (GTD-035)

## Technical specification

- ES modules only (PLAN Constraints); `.d.ts` generated from JSDoc via `tsc --noEmit` CI check.
- Rationale for fetch (not axios): zero deps, Node 18+ built-in; agent sizing done via undici dispatcher or node `http.Agent` as needed.

## Acceptance criteria

- [ ] `connect(port)` resolves against a live game; connection-refused → typed error
- [ ] Envelope errors surface as typed errors carrying `code`/`message`/`details`
- [ ] `tsc --noEmit` type-test passes in CI
- [ ] `js/core` has zero test-runner dependencies (enforced by dependency check)

## Testing

- [ ] Unit tests with a mocked fetch; integration smoke deferred to GTD-018.

## Documentation

- [ ] `js/core/README.md`: install, connect, error model.

## Files expected to change

```
js/package.json
js/core/package.json
js/core/src/client.js
js/core/README.md
```

## References

- SPEC §2 (envelope), §6.1 (pool sizing)
- PLAN §Monorepo Package Design, §Constraints (ES modules, JSDoc)
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:011]] [[dep:010]]

**Blocks:** [[dep:018]] [[dep:026]] [[dep:034]] [[dep:035]]
