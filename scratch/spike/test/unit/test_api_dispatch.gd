extends GdUnitTestSuite
## GTD-012 — dispatch funnel + FIFO ordering through the addon API layer.
##
## Proves: every request path goes through the dispatcher queue (main-thread
## execution), a crashed/malformed handler funnels to 500 INTERNAL_ERROR with
## the server staying up, and the queue drains FIFO under concurrent load.

const WORKERS := 3
const SUBMITS_PER_WORKER := 50


func _http_get(port: int, path: String, token: String = "") -> Dictionary:
	# HTTPRequest capture via connected lambda into a Dictionary (the known
	# gotcha: awaiting an already-emitted request_completed deadlocks).
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {}
	http.request_completed.connect(func(_r, code, _headers, body):
		result.code = code
		result.body = body.get_string_from_utf8())
	var headers := PackedStringArray()
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	http.request("http://127.0.0.1:%d%s" % [port, path], headers)
	var waited := 0
	while not result.has("code") and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func test_health_routes_through_dispatcher() -> void:
	# /health now goes worker → dispatcher.submit → main-thread _main_health.
	# A 200 with the exact shape proves the whole marshaling path works.
	var server: TestDriverServer = auto_free(TestDriverServer.new())
	add_child(server)
	server.setup(0, "")
	assert_bool(server.start()).is_true()
	var r: Dictionary = await _http_get(server.bound_port, "/health")
	assert_int(r.get("code", 0)).is_equal(200)
	var body: Dictionary = JSON.parse_string(r.body)
	assert_bool(body.ok).is_true()
	assert_str(body.data.status).is_equal("ok")
	server.stop()


func test_handler_crash_funnel_500_and_server_stays_up() -> void:
	var server: TestDriverServer = auto_free(TestDriverServer.new())
	add_child(server)
	server.setup(0, "")
	assert_bool(server.start()).is_true()
	# Register the malformed-result test hook (_main_boom returns null).
	server._api.routes["/boom"] = {"get": "boom"}
	server.register_routes()
	var r: Dictionary = await _http_get(server.bound_port, "/boom")
	assert_int(r.get("code", 0)).is_equal(500)
	var body: Dictionary = JSON.parse_string(r.body)
	assert_bool(body.ok).is_false()
	assert_str(body.error.code).is_equal("INTERNAL_ERROR")
	# The server must still be up and serving after the funnel.
	r = await _http_get(server.bound_port, "/health")
	assert_int(r.get("code", 0)).is_equal(200)
	server.stop()


func test_fifo_ordering_under_load() -> void:
	var dispatcher: TestDriverDispatcher = auto_free(TestDriverDispatcher.new())
	add_child(dispatcher)
	await get_tree().process_frame
	# Lambdas capture outer locals by VALUE — shared state goes through a
	# Dictionary (reference type).
	var log := {}
	for w in WORKERS:
		log["w%d" % w] = []
	var worker := func(worker_id: int) -> Variant:
		for i in SUBMITS_PER_WORKER:
			Dispatcher.submit(func() -> void:
				(log["w%d" % worker_id] as Array).append(i))
		return true
	var threads: Array[Thread] = []
	for w in WORKERS:
		var t := Thread.new()
		t.start(worker.bind(w))
		threads.append(t)
	var any_alive := true
	while any_alive:
		any_alive = false
		for t in threads:
			if t.is_alive():
				any_alive = true
		await get_tree().process_frame
	var total := 0
	for w in WORKERS:
		var seq: Array = log["w%d" % w]
		total += seq.size()
		# Per-worker FIFO: each worker's own submissions must land in order.
		for i in SUBMITS_PER_WORKER:
			assert_int(seq[i]).is_equal(i)
	assert_int(total).is_equal(WORKERS * SUBMITS_PER_WORKER)
	for t in threads:
		t.wait_to_finish()
