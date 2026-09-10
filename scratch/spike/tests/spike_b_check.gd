extends Node
## GTD-005 (Spike B) — click end-to-end validation.
##
## Instantiated by SpikeServer when launched with `-- --test-driver --self-test-b`.
## Checks (SPEC §6 routing + timing contract):
##   1. POST /input/click on /root/Main/Button → 200 {injected:true}.
##   2. Wait ≥1 frame (timing contract: 200 = injected, not processed),
##      then GET /node text via a /state-style read → label == "pressed".
##   3. Same for the SubViewportContainer fixture (2x stretch scale):
##      click /root/SubFixture/Container/Sub/Inner/Button lands on the
##      inner Control only if the coordinate transform is correct.
##   4. Click on a missing node → 404 NODE_NOT_FOUND.
## Runs identically windowed and headless (Viewport.push_input path).
## Prints SPIKE_B_OK and quits 0, or fails with exit code 1.

var _server: Node  # SpikeServer


func run(server: Node) -> void:
	_server = server
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures := 0

	# --- 1+2. Root-viewport button click ------------------------------------
	var c1: Dictionary = await _request("POST", "/input/click",
			"{\"path\": \"/root/Main/Button\"}")
	if c1.code != 200:
		failures += 1
		push_error("[b] FAIL: click Main/Button got %d (body %s)" % [c1.code, c1.body])
	else:
		var injected: bool = c1.parsed.get("data", {}).get("injected", false)
		if not injected:
			failures += 1
			push_error("[b] FAIL: click response missing injected:true: %s" % [c1.parsed])
	# Timing contract: 200 means injected; effects land on a later frame.
	await _wait_frames(2)
	var label_text: String = _read_label("/root/Main/Label")
	if label_text != "pressed":
		failures += 1
		push_error("[b] FAIL: Main/Label = '%s', expected 'pressed'" % label_text)

	# --- 3. SubViewportContainer (2x stretch) click --------------------------
	var c2: Dictionary = await _request("POST", "/input/click",
			"{\"path\": \"/root/SubFixture/Container/Sub/Inner/Button\"}")
	if c2.code != 200:
		failures += 1
		push_error("[b] FAIL: click SubViewport button got %d (body %s)" % [c2.code, c2.body])
	await _wait_frames(2)
	var inner_text: String = _read_label("/root/SubFixture/Container/Sub/Inner/Label")
	if inner_text != "pressed":
		failures += 1
		push_error("[b] FAIL: Inner/Label = '%s', expected 'pressed' (coordinate transform?)" % inner_text)

	# --- 4. Missing node → 404 ----------------------------------------------
	var c3: Dictionary = await _request("POST", "/input/click",
			"{\"path\": \"/root/DoesNotExist\"}")
	if c3.code != 404:
		failures += 1
		push_error("[b] FAIL: click missing node got %d, expected 404" % c3.code)
	else:
		var code: String = c3.parsed.get("error", {}).get("code", "")
		if code != "NODE_NOT_FOUND":
			failures += 1
			push_error("[b] FAIL: 404 body code = '%s'" % code)

	if failures > 0:
		push_error("[b] %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("SPIKE_B_OK")
	get_tree().quit(0)


## Read a Label's text through the Dispatcher (main-thread tree access).
func _read_label(node_path: String) -> String:
	var text: Variant = Dispatcher.submit(func() -> Variant:
		var n := get_tree().root.get_node_or_null(NodePath(node_path))
		return n.text if n != null else "<missing>")
	return str(text)


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _url(path: String) -> String:
	return "http://%s:%d%s" % [_server.BIND, _server.PORT, path]


func _make_http() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	return http


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
