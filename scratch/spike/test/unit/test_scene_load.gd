# GTD-023 — POST /scene/load (SPEC §5.0 readiness semantics).
#
# /scene/load mirrors /reset's readiness contract (200 only after the new
# scene is live + ready) but SKIPS the tween/orphan cleanup steps. The
# in-flight guard is shared with /reset (503 SERVER_BUSY).
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
	# Restore the main scene so later suites (alphabetical order) see a sane tree.
	await _post("/scene/load", {"path": MAIN_SCENE})


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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


func test_load_valid_scene_ready() -> void:
	var res := await _post("/scene/load", {"path": ALT_SCENE})
	assert_int(res["code"]).is_equal(200)
	var data: Dictionary = res["body"]["data"]
	assert_bool(data["scene_ready"]).is_true()
	# The tree reflects the new scene (GET /scene/current shape verified e2e).
	assert_str(get_tree().current_scene.scene_file_path).is_equal(ALT_SCENE)
	# The scene's script state is live (marker from alt_scene.gd).
	assert_str(str(get_tree().current_scene.get("marker"))).is_equal("loaded")


func test_load_errors() -> void:
	# Unknown scene → 404 SCENE_NOT_FOUND.
	var res := await _post("/scene/load", {"path": "res://nope/missing.tscn"})
	assert_int(res["code"]).is_equal(404)
	assert_str(str(res["body"]["error"]["code"])).is_equal("SCENE_NOT_FOUND")
	# Missing param → 400 MISSING_PARAM.
	res = await _post("/scene/load", {})
	assert_int(res["code"]).is_equal(400)
	assert_str(str(res["body"]["error"]["code"])).is_equal("MISSING_PARAM")
	# A non-scene resource → 404 SCENE_NOT_FOUND (PackedScene type check).
	res = await _post("/scene/load", {"path": "res://project.godot"})
	assert_int(res["code"]).is_equal(404)
	assert_str(str(res["body"]["error"]["code"])).is_equal("SCENE_NOT_FOUND")


func test_load_and_reset_share_in_flight_guard() -> void:
	# The in-flight guard is shared between /reset and /scene/load. Test it
	# deterministically: call the main-thread start-tasks back-to-back in the
	# SAME frame — the first launches its coroutine (which suspends at the
	# first await with the guard held), the second must see the guard and
	# return 503 SERVER_BUSY.
	var api: TestDriverApi = _server._api
	var slot := {"done": false, "result": null}
	var mutex := Mutex.new()
	var first: Dictionary = api._start_scene_load(ALT_SCENE, slot, mutex)
	assert_int(first["code"]).is_equal(200)
	var second: Dictionary = api._start_scene_load(ALT_SCENE, slot, mutex)
	assert_int(second["code"]).is_equal(503)
	assert_str(str(second["body"]["error"]["code"])).is_equal("SERVER_BUSY")
	# Also via the reset start-task (same guard).
	var third: Dictionary = api._start_reset("kill", slot, mutex)
	assert_int(third["code"]).is_equal(503)
	# Let the load coroutine finish (guard released, slot filled).
	var deadline := Time.get_ticks_msec() + 10000
	while not slot["done"] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_bool(slot["done"]).is_true()
	var result: Dictionary = slot["result"]
	assert_int(result["code"]).is_equal(200)
