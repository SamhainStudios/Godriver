# GTD-025 — GET /ui/layout/<path> (SPEC §5.1).
#
# Layout snapshot: get_global_rect() bounds (viewport-canvas coords), visibility,
# anchors, optional ?depth=N recursion, test_id query variant, error codes.
extends GdUnitTestSuite

const TestDriverServer := preload("res://addons/godriver/http_server.gd")

var _server: TestDriverServer


func before_test() -> void:
	var w: Variant = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h: Variant = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	get_tree().root.size = Vector2i(int(w), int(h))
	var old := get_tree().root.get_node_or_null("LayoutFixture")
	if old != null:
		get_tree().root.remove_child(old)
		old.free()
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	var old := get_tree().root.get_node_or_null("LayoutFixture")
	if old != null:
		get_tree().root.remove_child(old)
		old.free()


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


func _make_fixture() -> Node:
	var fixture := Node2D.new()
	fixture.name = "LayoutFixture"
	var panel := Control.new()
	panel.name = "Panel"
	panel.position = Vector2(30, 40)
	panel.size = Vector2(200, 100)
	var btn := Button.new()
	btn.name = "Btn"
	btn.position = Vector2(10, 20)
	btn.size = Vector2(80, 30)
	btn.set_meta("test_id", "layout_btn")
	panel.add_child(btn)
	fixture.add_child(panel)
	get_tree().root.add_child.call_deferred(fixture)
	await get_tree().process_frame
	await get_tree().process_frame
	return fixture


func test_layout_rect_matches_editor_rect() -> void:
	var fixture := await _make_fixture()
	var res := await _http_get("/ui/layout/root/LayoutFixture/Panel")
	assert_int(res["code"]).is_equal(200)
	var data: Dictionary = res["body"]["data"]
	assert_str(str(data["type"])).is_equal("Control")
	assert_bool(data["visible_in_tree"]).is_true()
	var rect: Dictionary = data["global_rect"]
	assert_float(rect["x"]).is_equal(30.0)
	assert_float(rect["y"]).is_equal(40.0)
	assert_float(rect["w"]).is_equal(200.0)
	assert_float(rect["h"]).is_equal(100.0)
	# depth 0 → no children key.
	assert_bool(data.has("children")).is_false()


func test_depth_recursion_and_test_id() -> void:
	var fixture := await _make_fixture()
	# depth=1 includes the child Button layout.
	var res := await _http_get("/ui/layout/root/LayoutFixture/Panel?depth=1")
	assert_int(res["code"]).is_equal(200)
	var data: Dictionary = res["body"]["data"]
	assert_int(data["children"].size()).is_equal(1)
	var child: Dictionary = data["children"][0]
	assert_str(str(child["type"])).is_equal("Button")
	var crect: Dictionary = child["global_rect"]
	assert_float(crect["x"]).is_equal(40.0)
	assert_float(crect["y"]).is_equal(60.0)
	# test_id query variant.
	res = await _http_get("/ui/layout?test_id=layout_btn")
	assert_int(res["code"]).is_equal(200)
	assert_str(str(res["body"]["data"]["type"])).is_equal("Button")


func test_error_codes() -> void:
	await _make_fixture()
	# Missing node → 404 NODE_NOT_FOUND.
	var res := await _http_get("/ui/layout/root/LayoutFixture/Nope")
	assert_int(res["code"]).is_equal(404)
	assert_str(str(res["body"]["error"]["code"])).is_equal("NODE_NOT_FOUND")
	# Non-Control → 400 BAD_TARGET (fixture root is a Node2D).
	res = await _http_get("/ui/layout/root/LayoutFixture")
	assert_int(res["code"]).is_equal(400)
	assert_str(str(res["body"]["error"]["code"])).is_equal("BAD_TARGET")
	# Unknown test_id → 404 TEST_ID_NOT_FOUND.
	res = await _http_get("/ui/layout?test_id=nope")
	assert_int(res["code"]).is_equal(404)
	assert_str(str(res["body"]["error"]["code"])).is_equal("TEST_ID_NOT_FOUND")
