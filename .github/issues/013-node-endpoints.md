---
title: GTD-013 · /node/<path> + property read
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 012
resolution: DONE 2026-09-10 — GET /node/<path> + GET /node/<path>/property/<name> live, 24/24 GdUnit green, e2e curl verified. Files: addons/godriver/handlers/node_handler.gd (TestDriverNodeHandler: resolve/summary/get_info/get_property; URL-decode helper; leading /root optional; absolute NodePath fix), addons/godriver/serializer.gd (TestDriverSerializer — canonical §4 implementation MOVED from scratch/spike/scripts/serializer.gd, which is deleted; test_serializer.gd preload updated), api_handler.gd (raw-regex route "^/node/(?<npath>.+?)[/#?]?$" → handler "node"; _extract_args reads named group from req.query_match on the worker thread; _main_node splits at LAST "/property/" → property read vs node info). New suite scratch/spike/test/unit/test_node_endpoints.gd (4 tests: info shape Button/Label/plain Node incl. test_id meta + children order; §4 property round-trips Vector2/Color/NodePath/String/bool/int; UNSUPPORTED_TYPE for Callable property; error codes NODE_NOT_FOUND / PROPERTY_NOT_FOUND incl. engine-private / BAD_PATH). Fixture scratch/spike/test/fixtures/props_node.gd (PropsNode). KEY FINDINGS: (1) UPSTREAM BUG PATCHED in addons/godottpd/http_server.gd register_router: router.path.left(0) → left(1) — left(0) returns "" so the raw-regex path feature was unreachable; logged in VENDORED.md deviation table (raw-regex routes + named groups via query_match now documented there). (2) NodePath resolution must be ABSOLUTE ("/" + path) — relative "root/..." from the tree root looks for a child named "root" and always 404s. (3) godottpd :param syntax is single-segment only ([^/#?]+?) — multi-segment node paths REQUIRE the raw-regex route. (4) GdUnit failure messages diff-render strings with <...> markers — mangled-looking output in failures is decoration, not corruption; print the raw body for ground truth. (5) Test helper named _get collides with Object._get(StringName) virtual (same as GTD-012) — use _http_get. (6) Fixture nodes live under the suite node, not /root — build request paths from _fixture.get_path(). Edge case documented: node named "property" as second-to-last path segment is ambiguous with the property-read form; prefer test_id queries.
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
addons/godriver/handlers/node_handler.gd
```

## References

- SPEC §4, §5
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:012]] [[dep:010]]

**Blocks:** [[dep:014]] [[dep:015]] [[dep:018]] [[dep:020]] [[dep:025]]
