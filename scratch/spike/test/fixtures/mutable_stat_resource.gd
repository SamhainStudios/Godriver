class_name MutableStatResource
extends Resource
## Fixture for the .tres cache-isolation self-test (GTD-007).
## Minimal mutable Resource: games commonly load .tres stats and mutate them,
## which pollutes the ResourceLoader cache (CACHE_MODE_REUSE) across scene
## changes. See SPEC §5.0 out-of-scope block and docs/technical/addon-internals.md.

@export var base_health: int = 100
