extends GdUnitTestSuite
## GTD-031 — Signal observation & waiting endpoints (/signal/watch, /signal/poll, /signal/wait)

var _server: TestDriverServer
var _fixture: Node


func before_test() -> void:
	TestDriverSignalHandler.clear_all()
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.free()
		_fixture = null
	var w: Variant = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h: Variant = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	get_tree().root.size = Vector2i(int(w), int(h))
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	_server.stop()
	TestDriverSignalHandler.clear_all()
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.free()
		_fixture = null


func _http_post(path: String, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {"code": 0, "body": ""}
	http.request_completed.connect(func(_r, code, _headers, b):
		result.code = code
		result.body = b.get_string_from_utf8())
	var headers := PackedStringArray(["Content-Type: application/json"])
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], headers, HTTPClient.METHOD_POST, body)
	var waited := 0
	while int(result.code) == 0 and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func _http_get(path: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {"code": 0, "body": ""}
	http.request_completed.connect(func(_r, code, _headers, b):
		result.code = code
		result.body = b.get_string_from_utf8())
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], [], HTTPClient.METHOD_GET)
	var waited := 0
	while int(result.code) == 0 and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func _parsed(r: Dictionary) -> Dictionary:
	return JSON.parse_string(r.body)


func _error(r: Dictionary) -> Dictionary:
	return _parsed(r).get("error", {})


class CustomNode extends Node:
	signal custom_event(message: String, count: int)


func _make_fixture() -> CustomNode:
	var node := CustomNode.new()
	node.name = "SignalNode"
	node.set_meta("test_id", "signal_target")
	_fixture = node
	add_child(node)
	return node


func test_watch_and_poll_signal() -> void:
	var node := _make_fixture()
	var node_path := String(node.get_path())

	var watch_res := await _http_post("/signal/watch", JSON.stringify({"path": node_path, "signal": "custom_event"}))
	assert_int(watch_res.code).is_equal(200)

	node.custom_event.emit("hello", 42)
	await get_tree().process_frame

	var poll_res := await _http_get("/signal/poll")
	assert_int(poll_res.code).is_equal(200)
	var data: Dictionary = _parsed(poll_res).get("data", {})
	var emissions: Array = data.get("emissions", [])
	assert_int(emissions.size()).is_equal(1)
	assert_str(str(emissions[0].get("target"))).is_equal(node_path)
	assert_str(str(emissions[0].get("signal"))).is_equal("custom_event")
	assert_array(emissions[0].get("args")).is_equal(["hello", 42.0])


func test_watch_by_test_id() -> void:
	var node := _make_fixture()

	var watch_res := await _http_post("/signal/watch", JSON.stringify({"test_id": "signal_target", "signal": "custom_event"}))
	assert_int(watch_res.code).is_equal(200)

	node.custom_event.emit("via_test_id", 100)
	await get_tree().process_frame

	var poll_res := await _http_get("/signal/poll")
	assert_int(poll_res.code).is_equal(200)
	var data: Dictionary = _parsed(poll_res).get("data", {})
	var emissions: Array = data.get("emissions", [])
	assert_int(emissions.size()).is_equal(1)
	assert_str(str(emissions[0].get("signal"))).is_equal("custom_event")


func test_unknown_signal_returns_400_signal_not_found() -> void:
	var node := _make_fixture()
	var watch_res := await _http_post("/signal/watch", JSON.stringify({"path": String(node.get_path()), "signal": "non_existent_signal"}))
	assert_int(watch_res.code).is_equal(400)
	assert_str(str(_error(watch_res).get("code"))).is_equal("SIGNAL_NOT_FOUND")


func test_signal_wait_timeout_returns_200_signaled_false() -> void:
	var node := _make_fixture()
	var node_path := String(node.get_path())

	await _http_post("/signal/watch", JSON.stringify({"path": node_path, "signal": "custom_event"}))

	var wait_res := await _http_post("/signal/wait", JSON.stringify({"path": node_path, "signal": "custom_event", "timeout": 0.2}))
	assert_int(wait_res.code).is_equal(200)
	var data: Dictionary = _parsed(wait_res).get("data", {})
	assert_bool(data.get("signaled", true)).is_false()
	assert_bool(data.get("timed_out", false)).is_true()


func test_signal_wait_blocks_and_resolves_on_fire() -> void:
	var node := _make_fixture()
	var node_path := String(node.get_path())

	await _http_post("/signal/watch", JSON.stringify({"path": node_path, "signal": "custom_event"}))

	# Launch wait request asynchronously
	var wait_task := Callable(self, "_http_post").bind("/signal/wait", JSON.stringify({"path": node_path, "signal": "custom_event", "timeout": 3.0}))

	# Emit signal shortly after wait begins
	get_tree().create_timer(0.05).timeout.connect(func(): node.custom_event.emit("async_fire", 99), CONNECT_ONE_SHOT)

	var wait_res: Dictionary = await wait_task.call()
	assert_int(wait_res.code).is_equal(200)
	var data: Dictionary = _parsed(wait_res).get("data", {})
	assert_bool(data.get("signaled", false)).is_true()
	var emission: Dictionary = data.get("emission", {})
	assert_str(str(emission.get("target"))).is_equal(node_path)
	assert_str(str(emission.get("signal"))).is_equal("custom_event")
	assert_array(emission.get("args")).is_equal(["async_fire", 99.0])


func test_reset_unblocks_pending_signal_waits() -> void:
	var node := _make_fixture()
	var node_path := String(node.get_path())

	await _http_post("/signal/watch", JSON.stringify({"path": node_path, "signal": "custom_event"}))

	# Launch wait request asynchronously
	var wait_task := Callable(self, "_http_post").bind("/signal/wait", JSON.stringify({"path": node_path, "signal": "custom_event", "timeout": 10.0}))

	# Trigger clear_all (simulating reset) shortly after wait begins
	get_tree().create_timer(0.05).timeout.connect(func(): TestDriverSignalHandler.clear_all(), CONNECT_ONE_SHOT)

	var wait_res: Dictionary = await wait_task.call()
	assert_int(wait_res.code).is_equal(200)
	var data: Dictionary = _parsed(wait_res).get("data", {})
	assert_bool(data.get("signaled", true)).is_false()
	assert_bool(data.get("reset", false)).is_true()
