extends GdUnitTestSuite
## GTD-032 — Server-side assertion endpoints (/assert/visible, /assert/enabled, /assert/property)

var _server: TestDriverServer
var _fixture: Node


func before_test() -> void:
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


func _parsed(r: Dictionary) -> Dictionary:
	return JSON.parse_string(r.body)


func _error(r: Dictionary) -> Dictionary:
	return _parsed(r).get("error", {})


func _make_fixture() -> Button:
	var btn := Button.new()
	btn.name = "AssertButton"
	btn.text = "Click Me"
	btn.set_meta("test_id", "assert_btn")
	_fixture = btn
	add_child(btn)
	return btn


func test_assert_visible_pass_and_fail() -> void:
	var btn := _make_fixture()
	var path := String(btn.get_path())

	# Visible by default -> expected true -> passed: true
	var res1 := await _http_post("/assert/visible", JSON.stringify({"path": path, "expected": true}))
	assert_int(res1.code).is_equal(200)
	var data1: Dictionary = _parsed(res1).get("data", {})
	assert_bool(data1.get("passed", false)).is_true()
	assert_bool(data1.get("actual", false)).is_true()

	# Set visible = false -> expected true -> passed: false
	btn.visible = false
	var res2 := await _http_post("/assert/visible", JSON.stringify({"path": path, "expected": true}))
	assert_int(res2.code).is_equal(200)
	var data2: Dictionary = _parsed(res2).get("data", {})
	assert_bool(data2.get("passed", true)).is_false()
	assert_bool(data2.get("actual", true)).is_false()

	# Set visible = false -> expected false -> passed: true
	var res3 := await _http_post("/assert/visible", JSON.stringify({"path": path, "expected": false}))
	assert_int(res3.code).is_equal(200)
	var data3: Dictionary = _parsed(res3).get("data", {})
	assert_bool(data3.get("passed", false)).is_true()


func test_assert_visible_by_test_id() -> void:
	var btn := _make_fixture()

	var res := await _http_post("/assert/visible", JSON.stringify({"test_id": "assert_btn", "expected": true}))
	assert_int(res.code).is_equal(200)
	var data: Dictionary = _parsed(res).get("data", {})
	assert_bool(data.get("passed", false)).is_true()


func test_assert_enabled_pass_and_fail() -> void:
	var btn := _make_fixture()
	var path := String(btn.get_path())

	# Enabled by default -> expected true -> passed: true
	var res1 := await _http_post("/assert/enabled", JSON.stringify({"path": path, "expected": true}))
	assert_int(res1.code).is_equal(200)
	var data1: Dictionary = _parsed(res1).get("data", {})
	assert_bool(data1.get("passed", false)).is_true()

	# Set disabled = true -> expected true -> passed: false
	btn.disabled = true
	var res2 := await _http_post("/assert/enabled", JSON.stringify({"path": path, "expected": true}))
	assert_int(res2.code).is_equal(200)
	var data2: Dictionary = _parsed(res2).get("data", {})
	assert_bool(data2.get("passed", true)).is_false()
	assert_bool(data2.get("actual", true)).is_false()

	# Set disabled = true -> expected false -> passed: true
	var res3 := await _http_post("/assert/enabled", JSON.stringify({"path": path, "expected": false}))
	assert_int(res3.code).is_equal(200)
	var data3: Dictionary = _parsed(res3).get("data", {})
	assert_bool(data3.get("passed", false)).is_true()


func test_assert_property_pass_and_fail() -> void:
	var btn := _make_fixture()
	var path := String(btn.get_path())

	# String property text == "Click Me"
	var res1 := await _http_post("/assert/property", JSON.stringify({"path": path, "property": "text", "expected": "Click Me"}))
	assert_int(res1.code).is_equal(200)
	var data1: Dictionary = _parsed(res1).get("data", {})
	assert_bool(data1.get("passed", false)).is_true()

	# String property text expected "Other" -> passed: false
	var res2 := await _http_post("/assert/property", JSON.stringify({"path": path, "property": "text", "expected": "Other"}))
	assert_int(res2.code).is_equal(200)
	var data2: Dictionary = _parsed(res2).get("data", {})
	assert_bool(data2.get("passed", true)).is_false()

	# Vector2 property position
	btn.position = Vector2(10, 20)
	var res3 := await _http_post("/assert/property", JSON.stringify({"path": path, "property": "position", "expected": {"x": 10.0, "y": 20.0}}))
	assert_int(res3.code).is_equal(200)
	var data3: Dictionary = _parsed(res3).get("data", {})
	assert_bool(data3.get("passed", false)).is_true()


func test_assert_property_missing_returns_404() -> void:
	var btn := _make_fixture()
	var path := String(btn.get_path())

	var res := await _http_post("/assert/property", JSON.stringify({"path": path, "property": "non_existent_prop", "expected": 123}))
	assert_int(res.code).is_equal(404)
	assert_str(str(_error(res).get("code"))).is_equal("PROPERTY_NOT_FOUND")


func test_assert_target_not_found_returns_404() -> void:
	var res := await _http_post("/assert/visible", JSON.stringify({"path": "/root/NonExistentNode", "expected": true}))
	assert_int(res.code).is_equal(404)
	assert_str(str(_error(res).get("code"))).is_equal("NODE_NOT_FOUND")
