extends Node
## GTD-006 (Spike C) self-test — test_id resolution over HTTP.
## Run: --headless --path . -- --test-driver --self-test-c
## Prints SPIKE_C_OK and exits 0 on success.

var _server: Node


func run(server: Node) -> void:
	_server = server
	var failures := 0

	# 1. Unique test_id → 200 + correct path.
	var r := await _request("/node?test_id=start_button")
	failures += _expect(r, 200, "unique test_id resolves")
	if r.code == 200:
		var path: String = r.body.get("data", {}).get("path", "")
		if not path.contains("TestIdFixture/Tagged"):
			failures += 1
			print("FAIL: unexpected path %s" % path)
		else:
			print("PASS: unique → %s" % path)

	# 2. Unknown test_id → 404 NODE_NOT_FOUND.
	r = await _request("/node?test_id=nope")
	failures += _expect(r, 404, "unknown test_id → 404")
	if r.code == 404 and r.body.get("error", {}).get("code", "") == "NODE_NOT_FOUND":
		print("PASS: 404 envelope code NODE_NOT_FOUND")
	elif r.code == 404:
		failures += 1
		print("FAIL: 404 but wrong error code: %s" % [r.body])

	# 3. Duplicate test_id → 409 AMBIGUOUS_MATCH with matching_paths.
	r = await _request("/node?test_id=dup_id")
	failures += _expect(r, 409, "duplicate test_id → 409")
	if r.code == 409:
		var err: Dictionary = r.body.get("error", {})
		var paths: Array = err.get("details", {}).get("matching_paths", [])
		if err.get("code", "") == "AMBIGUOUS_MATCH" and paths.size() == 2:
			print("PASS: 409 with matching_paths=%s" % [paths])
		else:
			failures += 1
			print("FAIL: 409 body wrong: %s" % [r.body])

	# 4. Untagged node is invisible to test_id scan (sanity: no false match).
	r = await _request("/node?test_id=Untagged")
	failures += _expect(r, 404, "node name is not a test_id")

	if failures == 0:
		print("SPIKE_C_OK")
		get_tree().quit(0)
	else:
		print("SPIKE_C_FAIL (%d failures)" % failures)
		get_tree().quit(1)


func _expect(r: Dictionary, want_code: int, label: String) -> int:
	if r.get("code", -1) == want_code:
		return 0
	print("FAIL: %s — want %d got %d: %s" % [label, want_code, r.get("code", -1), r.get("body")])
	return 1


## GET + parse envelope. Returns {code:int, body:Dictionary}.
func _request(path: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var err := http.request("http://127.0.0.1:9090%s" % path)
	if err != OK:
		http.queue_free()
		return {"code": -1, "body": {}}
	var result: Array = await http.request_completed
	http.queue_free()
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return {"code": result[1], "body": parsed if parsed is Dictionary else {}}
