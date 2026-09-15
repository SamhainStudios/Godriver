# Self-Tests

The Godriver specification includes self-test fixtures that validate engine-level behaviors documented in the spec.

## Resource Cache Isolation (SPEC §5.0)

**File**: [`spec/self-tests/test_resource_cache_isolation.gd`](https://github.com/samhainstudios/godot-test-driver/blob/master/spec/self-tests/test_resource_cache_isolation.gd)

This test validates the documented cross-scenario pollution vector: Godot's `ResourceLoader` with default `CACHE_MODE_REUSE` keeps mutated resources in the in-memory cache across `/reset`, and proves the `duplicate()` mitigation pattern.

### What it tests

1. **Cache pollution**: A `.tres` resource mutated via `ResourceLoader.load()` with `CACHE_MODE_REUSE` persists its mutated state across scenario resets.
2. **Isolation via `duplicate()`**: Creating a deep copy before mutation prevents the original cached resource from being modified.

### Running

This fixture is written against GUT (`extends GutTest`). For GdUnit4, swap the base class and assertion names:

| GUT | GdUnit4 |
|-----|---------|
| `extends GutTest` | `extends GdUnit4TestCase` |
| `assert_eq(a, b, msg)` | `assert_that(a).is_equal(b)` |
| `assert_ne(a, b, msg)` | `assert_that(a).is_not_equal(b)` |

### Fixture requirements

- `res://test/fixtures/mutable_stat_resource.tres` — a minimal `Resource` with an `int` property `base_health`
