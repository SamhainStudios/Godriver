---
title: GTD-017 · @godriver/core skeleton (fetch wrapper)
labels: area/client, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 011
resolution:
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
