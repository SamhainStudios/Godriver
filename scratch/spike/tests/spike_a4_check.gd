extends Node
## GTD-004 (Spike A4) — concurrency + paused-dispatch validation.
##
## Instantiated by SpikeServer when launched with `-- --test-driver --self-test-a4`.
## Checks (SPEC §6.1 + PLAN paused-dispatch resilience):
##   1. 1 blocked long-poll + 3 rapid /health — the 3 answer while the long-poll
##      is still pending (no head-of-line starvation).
##   2. MAX_BLOCKED_WAITS + 1 concurrent long-polls → the last gets 503 SERVER_BUSY.
##   3. Tree paused via POST /dev/pause → GET /node?path=/root/Main still 200.
##   4. Blocked-wait counter returns to 0 after all waits finish (no leak).
## Prints SPIKE_A4_OK and quits with exit code 0, or fails with exit code 1.

var _server: Node  # SpikeServer (PORT, BIND, MAX_BLOCKED_WAITS)


func run(server: Node) -> void:
	_server = server
	# The check (and its HTTPRequest children) must keep processing while the
	# tree is paused, else check 3 deadlocks.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures := 0

	# --- 1. One blocked long-poll must not starve rapid requests ------------
	var long_poll := _make_http()
	long_poll.request(_url("/wait/long?frames=120"))
	var t0 := Time.get_ticks_msec()
	for i in range(3):
		var r: Dictionary = await _request("GET", "/health")
		if r.code != 200:
			failures += 1
			push_error("[a4] FAIL: rapid /health %d got %d" % [i, r.code])
	var rapid_ms := Time.get_ticks_msec() - t0
	print("[a4] 3 rapid /health during long-poll: %d ms" % rapid_ms)
	if rapid_ms > 500:
		failures += 1
		push_error("[a4] FAIL: rapid requests starved behind long-poll (%d ms)" % rapid_ms)
	var lp_result: Array = await long_poll.request_completed
	if lp_result[1] != 200:
		failures += 1
		push_error("[a4] FAIL: long-poll itself returned %d" % lp_result[1])
	long_poll.queue_free()

	# --- 2. Cap: MAX_BLOCKED_WAITS + 1 long-polls → last gets 503 -----------
	# Results are captured via connected lambdas (awaiting an already-emitted
	# request_completed would deadlock).
	var blocked: Array[HTTPRequest] = []
	var blocked_codes := {}  # index -> status code
	for i in range(_server.MAX_BLOCKED_WAITS):
		var h := _make_http()
		var idx := i
		h.request_completed.connect(func(_r, code, _h, _b): blocked_codes[idx] = code)
		blocked.append(h)
		h.request(_url("/wait/long?frames=120"))
	# Wait until all 8 workers have actually entered their blocked state
	# (poll /health's blocked_waits counter) before firing the overflow.
	var waited := 0
	while waited < 200:
		var r: Dictionary = await _request("GET", "/health")
		if r.parsed.get("data", {}).get("blocked_waits", 0) >= _server.MAX_BLOCKED_WAITS:
			break
		await get_tree().process_frame
		waited += 1
	var overflow := _make_http()
	overflow.request(_url("/wait/long?frames=120"))
	var ov_result: Array = await overflow.request_completed
	if ov_result[1] != 503:
		failures += 1
		push_error("[a4] FAIL: overflow long-poll got %d, expected 503" % ov_result[1])
	else:
		var ov_body: Variant = JSON.parse_string(ov_result[3].get_string_from_utf8())
		if ov_body.get("error", {}).get("code", "") != "SERVER_BUSY":
			failures += 1
			push_error("[a4] FAIL: 503 body missing SERVER_BUSY code: %s" % [ov_body])
	overflow.queue_free()
	# Wait for the 8 blocked long-polls to finish (captured via lambdas).
	var wait_rounds := 0
	while blocked_codes.size() < blocked.size() and wait_rounds < 600:
		await get_tree().process_frame
		wait_rounds += 1
	for i in range(blocked.size()):
		var code: int = blocked_codes.get(i, -1)
		if code != 200:
			failures += 1
			push_error("[a4] FAIL: capped long-poll %d returned %d" % [i, code])
		blocked[i].queue_free()

	# --- 3. Paused dispatch end-to-end --------------------------------------
	var p1: Dictionary = await _request("POST", "/dev/pause", "{\"enabled\": true}")
	if p1.code != 200:
		failures += 1
		push_error("[a4] FAIL: /dev/pause(true) got %d" % p1.code)
	var n1: Dictionary = await _request("GET", "/node?path=/root/Main")
	if n1.code != 200:
		failures += 1
		push_error("[a4] FAIL: /node while paused got %d (body %s)" % [n1.code, n1.body])
	var n2: Dictionary = await _request("GET", "/node?path=/root/DoesNotExist")
	if n2.code != 404:
		failures += 1
		push_error("[a4] FAIL: missing node got %d, expected 404" % n2.code)
	var p2: Dictionary = await _request("POST", "/dev/pause", "{\"enabled\": false}")
	if p2.code != 200:
		failures += 1
		push_error("[a4] FAIL: /dev/pause(false) got %d" % p2.code)

	# --- 4. Blocked-wait counter must be back to 0 ---------------------------
	await get_tree().process_frame
	var h1: Dictionary = await _request("GET", "/health")
	var leaked: int = h1.parsed.get("data", {}).get("blocked_waits", -1)
	if leaked != 0:
		failures += 1
		push_error("[a4] FAIL: blocked_waits leaked: %d" % leaked)

	if failures > 0:
		push_error("[a4] %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("SPIKE_A4_OK")
	get_tree().quit(0)


func _url(path: String) -> String:
	return "http://%s:%d%s" % [_server.BIND, _server.PORT, path]


func _make_http() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	# Keep serving while the tree is paused (check 3 pauses the tree).
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	return http


## One request; returns {code: int, body: PackedByteArray, parsed: Variant}.
func _request(method: String, path: String, body: String = "") -> Dictionary:
	var http := _make_http()
	var err: int
	if method == "POST":
		err = http.request(_url(path), ["Content-Type: application/json"],
				HTTPClient.METHOD_POST, body)
	else:
		err = http.request(_url(path))
	if err != OK:
		http.queue_free()
		return {"code": -1, "body": PackedByteArray(), "parsed": {}}
	var result: Array = await http.request_completed
	http.queue_free()
	var parsed: Variant = JSON.parse_string(result[3].get_string_from_utf8())
	return {"code": result[1], "body": result[3],
			"parsed": parsed if typeof(parsed) == TYPE_DICTIONARY else {}}
