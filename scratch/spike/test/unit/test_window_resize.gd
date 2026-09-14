# GTD-053 - POST /window/resize + GET /window/state (SPEC §5.10).
#
# Runtime window resizing for responsive testing: size changes, stretch
# overrides, param validation, headless layout reflection.
extends GdUnitTestSuite

const TestDriverServer := preload("res://addons/godriver/http_server.gd")

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
	# Restore project-settings size + default stretch for later suites.
	var w: Variant = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h: Variant = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	get_tree().root.size = Vector2i(int(w), int(h))
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_tree().root.content_scale_factor = 1.0


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _http(method: String, path: String, body: Variant = null) -> Dictionary:
	var http: HTTPRequest = auto_free(HTTPRequest.new())
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var out := {}
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, b: PackedByteArray) -> void:
		out["code"] = code
		out["body"] = JSON.parse_string(b.get_string_from_utf8())
	)
	var err := http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], PackedStringArray(), HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, body if body is String else "")
	assert_int(err).is_equal(OK)
	var deadline := Time.get_ticks_msec() + 5000
	while not out.has("code") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return out


func _post(path: String, body: String) -> Dictionary:
	return await _http("POST", path, body)


func _err_code(r: Dictionary) -> String:
	return str(r.get("body", {}).get("error", {}).get("code", ""))


func test_resize_round_trip_and_state() -> void:
	var r := await _http("POST", "/window/resize", '{"width": 800, "height": 600}')
	assert_int(r.get("code", 0)).is_equal(200)
	var data: Dictionary = r.get("body", {}).get("data", {})
	assert_int(int(data.get("width", 0))).is_equal(800)
	assert_int(int(data.get("height", 0))).is_equal(600)
	var st := await _http("GET", "/window/state")
	assert_int(st.get("code", 0)).is_equal(200)
	var sdata: Dictionary = st.get("body", {}).get("data", {})
	assert_int(int(sdata.get("size", {}).get("width", 0))).is_equal(800)
	assert_int(int(sdata.get("size", {}).get("height", 0))).is_equal(600)
	var stretch: Dictionary = sdata.get("stretch", {})
	assert_str(str(stretch.get("mode", ""))).is_equal("disabled")
	assert_float(float(stretch.get("scale", 0.0))).is_equal(1.0)


func test_resize_param_validation() -> void:
	var missing := await _http("POST", "/window/resize", '{"height": 600}')
	assert_int(missing.get("code", 0)).is_equal(400)
	assert_str(_err_code(missing)).is_equal("TYPE_MISMATCH")
	var zero := await _http("POST", "/window/resize", '{"width": 0, "height": 600}')
	assert_int(zero.get("code", 0)).is_equal(400)
	assert_str(_err_code(zero)).is_equal("TYPE_MISMATCH")
	var negative := await _http("POST", "/window/resize", '{"width": -5, "height": 600}')
	assert_int(negative.get("code", 0)).is_equal(400)
	assert_str(_err_code(negative)).is_equal("TYPE_MISMATCH")
	var nonnum := await _http("POST", "/window/resize", '{"width": "big", "height": 600}')
	assert_int(nonnum.get("code", 0)).is_equal(400)
	assert_str(_err_code(nonnum)).is_equal("TYPE_MISMATCH")


func test_resize_stretch_overrides() -> void:
	var r := await _http("POST", "/window/resize", '{"width": 640, "height": 480, "stretch_mode": "canvas_items", "aspect": "keep_width", "scale": 2.0}')
	assert_int(r.get("code", 0)).is_equal(200)
	var data: Dictionary = r.get("body", {}).get("data", {})
	var stretch: Dictionary = data.get("stretch", {})
	assert_str(str(stretch.get("mode", ""))).is_equal("canvas_items")
	assert_str(str(stretch.get("aspect", ""))).is_equal("keep_width")
	assert_float(float(stretch.get("scale", 0.0))).is_equal(2.0)
	assert_int(get_tree().root.content_scale_mode).is_equal(Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)


func test_resize_invalid_stretch_strings() -> void:
	var bad_mode := await _http("POST", "/window/resize", '{"width": 640, "height": 480, "stretch_mode": "bogus"}')
	assert_int(bad_mode.get("code", 0)).is_equal(400)
	assert_str(_err_code(bad_mode)).is_equal("TYPE_MISMATCH")
	var expected: String = str(bad_mode.get("body", {}).get("error", {}).get("details", {}).get("expected", ""))
	assert_bool(expected.contains("canvas_items")).is_true()
	var bad_aspect := await _http("POST", "/window/resize", '{"width": 640, "height": 480, "aspect": "stretch"}')
	assert_int(bad_aspect.get("code", 0)).is_equal(400)
	assert_str(_err_code(bad_aspect)).is_equal("TYPE_MISMATCH")


func test_resize_headless_layout_reflection() -> void:
	# Headless: root.size change must be observable via /ui/layout bounds.
	var fixture := Control.new()
	fixture.name = "WinFixture"
	fixture.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(fixture)
	var r := await _http("POST", "/window/resize", '{"width": 1000, "height": 700}')
	assert_int(r.get("code", 0)).is_equal(200)
	await _wait_frames(2)
	var layout := await _http("GET", "/ui/layout/root/WinFixture")
	assert_int(layout.get("code", 0)).is_equal(200)
	var data: Dictionary = layout.get("body", {}).get("data", {})
	assert_int(int(data.get("size", {}).get("x", 0))).is_equal(1000)
	assert_int(int(data.get("size", {}).get("y", 0))).is_equal(700)
	assert_int(int(r.get("body", {}).get("data", {}).get("viewport_size", {}).get("width", 0))).is_equal(1000)
	get_tree().root.remove_child(fixture)
	fixture.free()

