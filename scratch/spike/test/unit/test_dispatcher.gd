extends GdUnitTestSuite
## GTD-007: dispatcher queue unit tests.
## Acceptance: submit() from a worker thread returns the value produced on the
## main thread; main-thread callers execute inline (deadlock avoidance).

const RESULT_SENTINEL := 42


func test_submit_from_thread_returns_main_thread_result() -> void:
	var worker := func() -> Variant:
		return Dispatcher.submit(func() -> int:
			# Must run on the main thread (drained by Dispatcher._process).
			assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
			return RESULT_SENTINEL)

	var t := Thread.new()
	t.start(worker)
	# Poll instead of wait_to_finish() from the main thread while the worker
	# may be blocked inside submit() — see docs/technical/addon-internals.md.
	while t.is_alive():
		await get_tree().process_frame
	var result: Variant = t.wait_to_finish()
	assert_int(result).is_equal(RESULT_SENTINEL)


func test_submit_from_main_thread_executes_inline() -> void:
	# Lambdas capture outer locals by VALUE — use a Dictionary (reference
	# type) so the callable's write is visible to the test body.
	var seen := {}
	var result: Variant = Dispatcher.submit(func() -> int:
		seen["tid"] = OS.get_thread_caller_id()
		return RESULT_SENTINEL)
	assert_int(result).is_equal(RESULT_SENTINEL)
	assert_int(seen["tid"]).is_equal(OS.get_main_thread_id())
