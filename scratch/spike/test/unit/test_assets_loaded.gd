# GTD-024 — GET /assets/loaded (SPEC §5.9a).
#
# Decision gate: ResourceLoader.list_handled_resources() does NOT exist on
# 4.7.2 — the endpoint reports the engine-wide resource COUNT (Performance
# monitor) plus the DRIVER-TRACKED inventory (scene loads via /scene/load
# and /reset), paginated.
extends GdUnitTestSuite

const TestDriverServer := preload("res://addons/godriver/http_server.gd")

const ALT_SCENE := "res://scratch/spike/test/fixtures/alt_scene.tscn"
const MAIN_SCENE := "res://scratch/spike/scenes/main.tscn"

var _server: TestDriverServer


func before_test() -> void:
	var w: Variant = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h: Variant = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	get_tree().root.size = Vector2i(int(w), int(h))
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	await _post("/scene/load", {"path": MAIN_SCENE})


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _http_get(path: String) -> Dictionary:
	var http: HTTPRequest = auto_free(HTTPRequest.new())
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var out := {}
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, b: PackedByteArray) -> void:
		out["code"] = code
		out["body"] = JSON.parse_string(b.get_string_from_utf8())
	)
	var err := http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path])
	assert_int(err).is_equal(OK)
	var deadline := Time.get_ticks_msec() + 5000
	while not out.has("code") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return out


func _post(path: String, body: Dictionary) -> Dictionary:
	var http: HTTPRequest = auto_free(HTTPRequest.new())
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var out := {}
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, b: PackedByteArray) -> void:
		out["code"] = code
		out["body"] = JSON.parse_string(b.get_string_from_utf8())
	)
	var err := http.request(
		"http://127.0.0.1:%d%s" % [_server.bound_port, path],
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(body),
	)
	assert_int(err).is_equal(OK)
	var deadline := Time.get_ticks_msec() + 20000
	while not out.has("code") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return out


func test_shape_and_tracked_inventory() -> void:
	var res := await _http_get("/assets/loaded")
	assert_int(res["code"]).is_equal(200)
	var data: Dictionary = res["body"]["data"]
	# Engine-wide count is a positive int (Performance monitor).
	assert_float(data["count"]).is_greater(0.0)
	# Tracked inventory starts empty in this suite (static state is fresh
	# per script load; other suites' loads happened in their own runs).
	var before: int = data["meta"]["total"]
	# A scene load is tracked.
	await _post("/scene/load", {"path": ALT_SCENE})
	res = await _http_get("/assets/loaded")
	data = res["body"]["data"]
	assert_float(data["meta"]["total"]).is_equal(float(before + 1))
	var last: Dictionary = data["resources"][data["resources"].size() - 1]
	assert_str(str(last["path"])).is_equal(ALT_SCENE)
	assert_str(str(last["source"])).is_equal("scene_load")


func test_pagination_and_errors() -> void:
	await _post("/scene/load", {"path": ALT_SCENE})
	# limit=1 returns at most one entry with meta.total intact.
	var res := await _http_get("/assets/loaded?limit=1")
	assert_int(res["code"]).is_equal(200)
	var data: Dictionary = res["body"]["data"]
	assert_int(data["resources"].size()).is_equal(1)
	assert_float(data["meta"]["total"]).is_greater(0.0)
	# Out-of-range limit → 400 TYPE_MISMATCH.
	res = await _http_get("/assets/loaded?limit=1001")
	assert_int(res["code"]).is_equal(400)
	assert_str(str(res["body"]["error"]["code"])).is_equal("TYPE_MISMATCH")
