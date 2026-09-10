---
title: GTD-013 · /node/<path> + property read
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 012
resolution:
---

# GTD-013 · `/node/<path>` + `/node/<path>/property/<name>`

## Context

Node discovery is the read backbone of the API — every later feature (input targeting, assertions, layout) builds on it.

## Goal

Node info and property read endpoints per SPEC §5, with §4 Variant shapes round-tripping exactly.

## Scope

**In scope:**

- `GET /node/<path>`: type, children, properties (per SPEC §5 shape)
- `GET /node/<path>/property/<name>`: `{value: <variant>}` serialized per §4
- Unknown node → 404; unknown property → 404 (distinct error codes per Appendix A)

**Out of scope:**

- test_id/group queries (GTD-014), writes (Phase 3)

## Technical specification

- Serializer from GTD-007 property tests is the single §4 implementation — handlers call it, never inline-serialize.
- Path parsing: URL-decoded node path segments; leading `/root` optional (SPEC §5 convention).

## Acceptance criteria

- [ ] Node info matches SPEC §5 shape for a Button, a Label, and a plain Node
- [ ] Property read returns §4-correct JSON for Vector2, Color, String, bool, NodePath
- [ ] Non-existent path → 404 NODE_NOT_FOUND; existing node, unknown property → 404 PROPERTY_NOT_FOUND
- [ ] No crash on any malformed path (400)

## Testing

- [ ] Self-tests: shape assertions per node type; serializer round-trip via live endpoint; error codes.

## Documentation

- [ ] SPEC §5 entries for both endpoints (from GTD-010) verified against implementation; `curl` examples executed.

## Files expected to change

```
addons/godot-test-driver/handlers/node_handler.gd
```

## References

- SPEC §4, §5
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:012]] [[dep:010]]

**Blocks:** [[dep:014]] [[dep:015]] [[dep:018]] [[dep:020]] [[dep:025]]
