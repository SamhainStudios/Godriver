extends GdUnitTestSuite
## GTD-020 — POST /input/click (SPEC §5.3/§6): targeted mouse injection.
## Covers root-viewport clicks, SubViewportContainer-embedded clicks,
## test_id targeting, and the error codes (MISSING_PARAM / NODE_NOT_FOUND /
## TEST_ID_NOT_FOUND / AMBIGUOUS_TEST_ID / BAD_TARGET).

var _server: TestDriverServer
var _fixture: Node


func before_test() -> void:
	# Suite node persists across tests — drop the previous fixture.
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.queue_free()
		await get_tree().process_frame
	# Headless root Window is 64x64 (GTD-005 finding): positions outside the
	# rect are treated as mouse-exit and hover is dropped. The shipped driver
	# fixes root.size at startup (driver.gd); the dormant test autoload does
	# not, so emulate it here from the project settings.
	var w: Variant = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h: Variant = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	get_tree().root.size = Vector2i(int(w), int(h))
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	_server.stop()


func _http_post(path: String, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {}
	http.request_completed.connect(func(_r, code, _headers, b):
		result.code = code
		result.body = b.get_string_from_utf8())
	var headers := PackedStringArray(["Content-Type: application/json"])
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], headers, HTTPClient.METHOD_POST, body)
	var waited := 0
	while not result.has("code") and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func _parsed(r: Dictionary) -> Dictionary:
	return JSON.parse_string(r.body)


func _error(r: Dictionary) -> Dictionary:
	return _parsed(r).get("error", {})


## Root-viewport fixture: Button + Label wired pressed → label "pressed".
func _make_root_fixture() -> Node:
	var root_ctrl := Control.new()
	root_ctrl.name = "ClickFixture"
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var button := Button.new()
	button.name = "Btn"
	button.position = Vector2(20, 20)
	button.size = Vector2(100, 40)
	var label := Label.new()
	label.name = "Lbl"
	label.position = Vector2(20, 80)
	button.pressed.connect(func(): label.text = "pressed")
	root_ctrl.add_child(button)
	root_ctrl.add_child(label)
	add_child(root_ctrl)
	return root_ctrl


## SubViewportContainer fixture mirroring the spike scene: container > sub >
## inner Control > Button + Label (pressed → inner label "pressed").
func _make_sub_fixture() -> Node:
	var holder := Control.new()
	holder.name = "SubClickFixture"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var container := SubViewportContainer.new()
	container.name = "Container"
	container.position = Vector2(10, 10)
	container.size = Vector2(200, 200)
	container.stretch = true
	var sub := SubViewport.new()
	sub.name = "Sub"
	var inner := Control.new()
	inner.name = "Inner"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var button := Button.new()
	button.name = "InnerBtn"
	button.position = Vector2(50, 80)
	button.size = Vector2(100, 40)
	var label := Label.new()
	label.name = "InnerLbl"
	label.position = Vector2(50, 140)
	button.pressed.connect(func(): label.text = "pressed")
	inner.add_child(button)
	inner.add_child(label)
	sub.add_child(inner)
	container.add_child(sub)
	holder.add_child(container)
	add_child(holder)
	return holder


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func test_click_root_viewport_button() -> void:
	var fixture := _make_root_fixture()
	await _wait_frames(2)  # let layout settle so get_global_rect is valid
	var btn_path := String(fixture.get_node("Btn").get_path())
	var r: Dictionary = await _http_post("/input/click", '{"path": "%s"}' % btn_path)
	assert_int(r.get("code", 0)).is_equal(200)
	var d: Dictionary = _parsed(r).get("data", {})
	assert_bool(d.get("injected", false)).is_true()
	assert_str(str(d.get("target"))).is_equal(btn_path)
	await _wait_frames(2)
	var lbl_text: String = fixture.get_node("Lbl").text
	print("GTD020_DEBUG label raw='", lbl_text, "' len=", lbl_text.length())
	assert_str(lbl_text).is_equal("pressed")


func test_click_subviewport_embedded_button() -> void:
	var fixture := _make_sub_fixture()
	await _wait_frames(2)
	var btn_path := String(fixture.get_node("Container/Sub/Inner/InnerBtn").get_path())
	var r: Dictionary = await _http_post("/input/click", '{"path": "%s"}' % btn_path)
	assert_int(r.get("code", 0)).is_equal(200)
	await _wait_frames(2)
	assert_str(str(fixture.get_node("Container/Sub/Inner/InnerLbl").text)).is_equal("pressed")


func test_click_by_test_id() -> void:
	var fixture := _make_root_fixture()
	fixture.get_node("Btn").set_meta("test_id", "gtd020_btn")
	await _wait_frames(2)
	var r: Dictionary = await _http_post("/input/click", '{"test_id": "gtd020_btn"}')
	assert_int(r.get("code", 0)).is_equal(200)
	await _wait_frames(2)
	assert_str(str(fixture.get_node("Lbl").text)).is_equal("pressed")


func test_click_error_codes() -> void:
	var fixture := _make_root_fixture()
	await _wait_frames(2)
	# Both path and test_id → 400 MISSING_PARAM.
	var r: Dictionary = await _http_post("/input/click", '{"path": "/root/x", "test_id": "y"}')
	assert_int(r.get("code", 0)).is_equal(400)
	assert_str(str(_error(r).get("code"))).is_equal("MISSING_PARAM")
	# Neither → 400 MISSING_PARAM.
	r = await _http_post("/input/click", "{}")
	assert_int(r.get("code", 0)).is_equal(400)
	# Unknown path → 404 NODE_NOT_FOUND.
	r = await _http_post("/input/click", '{"path": "/root/DefinitelyNotHere"}')
	assert_int(r.get("code", 0)).is_equal(404)
	assert_str(str(_error(r).get("code"))).is_equal("NODE_NOT_FOUND")
	# Unknown test_id → 404 TEST_ID_NOT_FOUND.
	r = await _http_post("/input/click", '{"test_id": "nope"}')
	assert_int(r.get("code", 0)).is_equal(404)
	assert_str(str(_error(r).get("code"))).is_equal("TEST_ID_NOT_FOUND")
	# Ambiguous test_id → 409 with matches.
	fixture.get_node("Btn").set_meta("test_id", "gtd020_dup")
	var btn2 := Button.new()
	btn2.name = "Btn2"
	btn2.set_meta("test_id", "gtd020_dup")
	fixture.add_child(btn2)
	await _wait_frames(1)
	r = await _http_post("/input/click", '{"test_id": "gtd020_dup"}')
	assert_int(r.get("code", 0)).is_equal(409)
	assert_str(str(_error(r).get("code"))).is_equal("AMBIGUOUS_TEST_ID")
	assert_int((_error(r).get("details", {}).get("matches", []) as Array).size()).is_equal(2)
	# Non-Control target → 400 BAD_TARGET (the Label is not a Control? it is —
	# use the fixture root Control's parent suite node, a plain Node).
	r = await _http_post("/input/click", '{"path": "%s"}' % String(get_tree().root.get_path()))
	assert_int(r.get("code", 0)).is_equal(400)
	assert_str(str(_error(r).get("code"))).is_equal("BAD_TARGET")
