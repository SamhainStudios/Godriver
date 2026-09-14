# GTD-054 - POST /input/key_down + /input/key_up (SPEC §5.3).
#
# Held-key testing: key_down leaves the action pressed across frames
# (observable via Input.is_action_pressed), key_up releases it.
extends GdUnitTestSuite

const TestDriverServer := preload("res://addons/godriver/http_server.gd")

var _server: TestDriverServer


func before_test() -> void:
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _http(method: String, path: String, body: String = "") -> Dictionary:
	var http: HTTPRequest = auto_free(HTTPRequest.new())
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var out := {}
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, b: PackedByteArray) -> void:
		out["code"] = code
		out["body"] = JSON.parse_string(b.get_string_from_utf8())
	)
	var m := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var err := http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], PackedStringArray(), m, body)
	assert_int(err).is_equal(OK)
	var deadline := Time.get_ticks_msec() + 5000
	while not out.has("code") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return out


func _err_code(r: Dictionary) -> String:
	return str(r.get("body", {}).get("error", {}).get("code", ""))


func test_key_down_holds_action_across_frames() -> void:
	var down := await _http("POST", "/input/key_down", '{"key": "ui_accept"}')
	assert_int(down.get("code", 0)).is_equal(200)
	var data: Dictionary = down.get("body", {}).get("data", {})
	assert_bool(data.get("pressed", false)).is_true()
	# Held state observable across MULTIPLE frames (the whole point vs /input/key).
	await _wait_frames(2)
	assert_bool(Input.is_action_pressed("ui_accept")).is_true()
	await _wait_frames(2)
	assert_bool(Input.is_action_pressed("ui_accept")).is_true()
	# Release.
	var up := await _http("POST", "/input/key_up", '{"key": "ui_accept"}')
	assert_int(up.get("code", 0)).is_equal(200)
	assert_bool(Input.is_action_pressed("ui_accept")).is_false()


func test_key_up_without_down_is_harmless() -> void:
	var up := await _http("POST", "/input/key_up", '{"key": "ui_accept"}')
	assert_int(up.get("code", 0)).is_equal(200)
	assert_bool(Input.is_action_pressed("ui_accept")).is_false()


func test_error_codes_match_input_key() -> void:
	var missing := await _http("POST", "/input/key_down", '{}')
	assert_int(missing.get("code", 0)).is_equal(400)
	assert_str(_err_code(missing)).is_equal("MISSING_PARAM")
	var unknown := await _http("POST", "/input/key_down", '{"key": "NOT_A_KEY"}')
	assert_int(unknown.get("code", 0)).is_equal(400)
	assert_str(_err_code(unknown)).is_equal("UNKNOWN_KEY")
	var unknown_up := await _http("POST", "/input/key_up", '{"key": "NOT_A_KEY"}')
	assert_int(unknown_up.get("code", 0)).is_equal(400)
	assert_str(_err_code(unknown_up)).is_equal("UNKNOWN_KEY")


func test_key_down_by_key_constant() -> void:
	var down := await _http("POST", "/input/key_down", '{"key": "KEY_ENTER"}')
	assert_int(down.get("code", 0)).is_equal(200)
	var data: Dictionary = down.get("body", {}).get("data", {})
	assert_int(int(data.get("device", -1))).is_equal(16)  # DEVICE_ID_KEYBOARD on 4.7+
	await _wait_frames(1)
	var up := await _http("POST", "/input/key_up", '{"key": "KEY_ENTER"}')
	assert_int(up.get("code", 0)).is_equal(200)
