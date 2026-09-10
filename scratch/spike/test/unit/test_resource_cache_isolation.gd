extends GdUnitTestSuite
## GTD-007: .tres cache-isolation fixture (ported from the GUT reference in
## spec/self-tests/test_resource_cache_isolation.gd — original kept verbatim).
##
## Documents the ResourceLoader cache-pollution hazard (SPEC §5.0 out-of-scope
## block): ResourceLoader defaults to CACHE_MODE_REUSE, so a mutated cached
## .tres survives scene changes / reloads while its refcount > 0.
##
## Case 1 (leak): mutating the loaded resource in place is visible to a later
## load — this is the pollution a game can hit in production.
## Case 2 (safe): duplicate(true) before mutation keeps the cached copy pristine.

const RES_PATH := "res://scratch/spike/test/fixtures/mutable_stat_resource.tres"


func test_tres_mutation_leaks_without_duplicate() -> void:
	var res: Resource = load(RES_PATH)
	assert_int(res.base_health).is_equal(100)
	res.base_health = 999
	var reloaded: Resource = load(RES_PATH)
	# Pollution documented: the cache hands back the mutated value.
	assert_int(reloaded.base_health).is_equal(999)


func test_tres_safe_mutation_using_duplicate() -> void:
	var res: Resource = load(RES_PATH)
	var copy: Resource = res.duplicate(true)
	copy.base_health = 50
	var reloaded: Resource = load(RES_PATH)
	# The cached copy must NOT have picked up the duplicate's mutation.
	assert_int(reloaded.base_health).is_not_equal(50)
