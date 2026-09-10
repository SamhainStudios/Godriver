extends Node
## GTD-002 (Spike A2) self-test — main-thread dispatcher task queue.
##
## Instantiated by SpikeServer when launched with `-- --test-driver --self-test-a2`.
## Checks:
##   1. HTTP worker-thread request marshals a scene query through Dispatcher
##      and returns the correct value (real godottpd worker thread).
##   2. Raw Thread submit: handler executed on the main thread, result correct.
##   3. Dispatcher still drains while the tree is paused (PROCESS_MODE_ALWAYS).
##   4. Game loop unblocked while serving requests (frame-count sanity).
## Prints SPIKE_A2_OK and quits with exit code 0, or fails with exit code 1.

var _server: Node  # SpikeServer (provides _query, _frames, PORT/BIND)


func run(server: Node) -> void:
	_server = server
	var failures := 0

	# --- 1. HTTP worker -> Dispatcher -> main thread round trip -------------
	var err: int = await _server._query("/scene/current")
	if err != OK:
		failures += 1
		push_error("[a2] FAIL: /scene/current over HTTP failed (%s)" % err)

	# --- 2. Raw thread submit: main-thread execution + correct result -------
	var main_id: int = _server.get_main_thread_id()
	var thread := Thread.new()
	var captured := {}  # filled by the worker: {handler_thread_id, scene}
	thread.start(_thread_body.bind(captured))
	# Poll across frames instead of wait_to_finish(): blocking the main thread
	# here would deadlock — the worker is waiting for the main thread to drain
	# the dispatcher queue, which only happens in _process.
	while thread.is_alive():
		await get_tree().process_frame
	var scene_name: Variant = thread.wait_to_finish()
	if scene_name != "Main":
		failures += 1
		push_error("[a2] FAIL: thread submit returned %s, expected Main" % [scene_name])
	if captured.get("handler_thread_id", -1) != main_id:
		failures += 1
		push_error("[a2] FAIL: handler ran on thread %s, main is %s"
				% [captured.get("handler_thread_id"), main_id])

	# --- 3. Drains while paused ---------------------------------------------
	get_tree().paused = true
	var paused_result: Variant = await thread_paused_query()
	get_tree().paused = false
	if paused_result != "Main":
		failures += 1
		push_error("[a2] FAIL: dispatcher did not drain while paused (got %s)" % [paused_result])

	# --- 4. Game loop unblocked while serving -------------------------------
	var frames_before: int = _server._frames
	for i in range(20):
		err = await _server._query("/scene/current")
		if err != OK:
			failures += 1
			push_error("[a2] FAIL: request %d failed (%s)" % [i, err])
	var frames_elapsed: int = _server._frames - frames_before
	print("[a2] frames elapsed during 20 sequential requests: %d" % frames_elapsed)
	if frames_elapsed < 10:
		failures += 1
		push_error("[a2] FAIL: main loop starved while serving (%d frames)" % frames_elapsed)

	if failures > 0:
		push_error("[a2] %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("SPIKE_A2_OK")
	get_tree().quit(0)


## Runs on a worker thread: submits a scene query through the Dispatcher.
func _thread_body(captured: Dictionary) -> Variant:
	captured["handler_thread_id"] = -1  # replaced inside the dispatched callable
	return Dispatcher.submit(func() -> Variant:
		captured["handler_thread_id"] = OS.get_thread_caller_id()
		return get_tree().current_scene.name)


## Paused-drain check: submit from a worker thread while the tree is paused.
## Main thread polls (never blocks) so the dispatcher can keep draining.
func thread_paused_query() -> Variant:
	var thread := Thread.new()
	thread.start(func() -> Variant:
		return Dispatcher.submit(func() -> Variant:
			return get_tree().current_scene.name)
	)
	while thread.is_alive():
		await get_tree().process_frame
	return thread.wait_to_finish()
