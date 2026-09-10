# Sprint 0 self-test fixture — `.tres` ResourceLoader cache isolation (SPEC §5.0 / rev 6)
#
# Validates the documented cross-scenario pollution vector: ResourceLoader's
# default CACHE_MODE_REUSE keeps mutated resources in the in-memory cache
# across /reset, and proves the duplicate() mitigation pattern.
#
# NOTE: written against GUT (extends GutTest). For GdUnit4, swap the base
# class and assertion names (assert_eq/assert_ne -> assert_that / is_equal)
# when the self-test scaffold is wired up in Sprint 0.
#
# Requires fixture: res://test/fixtures/mutable_stat_resource.tres
# (a minimal Resource with an int property `base_health`)

extends GutTest

const FIXTURE_PATH = "res://test/fixtures/mutable_stat_resource.tres"


func test_tres_mutation_leaks_without_duplicate() -> void:
	var res1 = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	res1.set("base_health", 999)

	# Simulate a scenario reset without cache eviction
	var res2 = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	assert_eq(res2.get("base_health"), 999, "Documents engine-level CACHE_MODE_REUSE pollution")


func test_tres_safe_mutation_using_duplicate() -> void:
	var original = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	var isolated_copy = original.duplicate(true)

	# Target state mutations to the duplicate instance
	isolated_copy.set("base_health", 50)
	assert_eq(isolated_copy.get("base_health"), 50)

	# Verify cached resource on disk remains pristine
	var reloaded = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	assert_ne(reloaded.get("base_health"), 50, "Pristine resource must not be modified by duplicate mutation")
