# GTD-021 — POST /input/type + POST /input/key (SPEC §5.3/§6).
#
# Fixtures:
#   - TypeFixture: Control(IGNORE) > LineEdit — typing target.
#   - KeyFixture: Control(IGNORE) > Btn Button + Lbl Label — ui_accept on a
#     focused Button fires `pressed`.
#   - ActionProbe: Node recording Input.is_action_pressed("ui_accept") each
#     _process — proves the global parse+flush path updates action state
#     headless (godot#73557 workaround).
extends GdUnitTestSuite

const TestDriverServer := preload("res://addons/godriver/http_server.gd")

var _server: TestDriverServer


func before_test() -> void:
	# Headless root Window is 64x64 by default — hover/press delivery treats
	# positions outside the rect as mouse-exit. Size it like the real game
	# (GTD-005/GTD-020 finding). Variant-typed: ProjectSettings returns Variant.
	var w: Variant = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h: Variant = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	get_tree().root.size = Vector2i(int(w), int(h))
	# Suite node persists across tests — free the previous fixture first.
	var old := get_tree().root.get_node_or_null("TypeKeyFixture")
	if old != null:
		get_tree().root.remove_child(old)
		old.free()
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	var old := get_tree().root.get_node_or_null("TypeKeyFixture")
	if old != null:
		get_tree().root.remove_child(old)
		old.free()


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _http_post(path: String, body: Dictionary) -> Dictionary:
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
	var deadline := Time.get_ticks_msec() + 5000
	while not out.has("code") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return out


func _make_fixture() -> Node:
	var fixture := Node2D.new()
	fixture.name = "TypeKeyFixture"

	var type_root := Control.new()
	type_root.name = "TypeRoot"
	type_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_root.position = Vector2(10, 10)
	var line_edit := LineEdit.new()
	line_edit.name = "Edit"
	line_edit.position = Vector2(0, 0)
	line_edit.size = Vector2(200, 40)
	type_root.add_child(line_edit)
	fixture.add_child(type_root)

	var key_root := Control.new()
	key_root.name = "KeyRoot"
	key_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_root.position = Vector2(10, 100)
	var btn := Button.new()
	btn.name = "Btn"
	btn.position = Vector2(0, 0)
	btn.size = Vector2(100, 40)
	var lbl := Label.new()
	lbl.name = "Lbl"
	lbl.position = Vector2(0, 60)
	btn.pressed.connect(func() -> void: lbl.text = "pressed")
	key_root.add_child(btn)
	key_root.add_child(lbl)
	fixture.add_child(key_root)

	var probe := Node.new()
	probe.name = "ActionProbe"
	probe.set_script(load("res://scratch/spike/test/fixtures/action_probe.gd"))
	fixture.add_child(probe)

	get_tree().root.add_child.call_deferred(fixture)
	await get_tree().process_frame
	await get_tree().process_frame
	return fixture


func test_type_into_line_edit_headless() -> void:
	var fixture := await _make_fixture()
	var edit: LineEdit = fixture.get_node("TypeRoot/Edit")
	var res := await _http_post("/input/type", {"path": "/root/TypeKeyFixture/TypeRoot/Edit", "text": "hello"})
	assert_int(res["code"]).is_equal(200)
	var data: Dictionary = res["body"]["data"]
	# JSON.parse_string delivers ints as floats (GTD-007 gotcha).
	assert_float(data["chars"]).is_equal(5.0)
	await _wait_frames(2)
	assert_str(edit.text).is_equal("hello")


func test_key_ui_accept_fires_focused_button_headless() -> void:
	var fixture := await _make_fixture()
	var btn: Button = fixture.get_node("KeyRoot/Btn")
	var lbl: Label = fixture.get_node("KeyRoot/Lbl")
	# Focus the button, then inject the action key globally.
	btn.grab_focus()
	await _wait_frames(1)
	var res := await _http_post("/input/key", {"key": "ui_accept"})
	assert_int(res["code"]).is_equal(200)
	var data: Dictionary = res["body"]["data"]
	# JSON ints arrive as floats (GTD-007 gotcha).
	assert_float(data["device"]).is_equal(16.0)
	await _wait_frames(2)
	assert_str(lbl.text).is_equal("pressed")


func test_key_global_updates_action_state_headless() -> void:
	var fixture := await _make_fixture()
	var probe: Node = fixture.get_node("ActionProbe")
	var res := await _http_post("/input/key", {"key": "ui_accept"})
	assert_int(res["code"]).is_equal(200)
	await _wait_frames(3)
	# The probe records is_action_pressed("ui_accept") in _process — the
	# press must have been visible to the engine's action state.
	assert_bool(probe.saw_pressed).is_true()


func test_key_by_constant_name() -> void:
	var fixture := await _make_fixture()
	var btn: Button = fixture.get_node("KeyRoot/Btn")
	var lbl: Label = fixture.get_node("KeyRoot/Lbl")
	btn.grab_focus()
	await _wait_frames(1)
	var res := await _http_post("/input/key", {"key": "KEY_ENTER", "path": "/root/TypeKeyFixture/KeyRoot/Btn"})
	assert_int(res["code"]).is_equal(200)
	await _wait_frames(2)
	assert_str(lbl.text).is_equal("pressed")


func test_error_codes() -> void:
	await _make_fixture()
	# Unknown key name.
	var res := await _http_post("/input/key", {"key": "KEY_NOT_A_THING"})
	assert_int(res["code"]).is_equal(400)
	assert_str(str(res["body"]["error"]["code"])).is_equal("UNKNOWN_KEY")
	# Missing key param.
	res = await _http_post("/input/key", {})
	assert_int(res["code"]).is_equal(400)
	assert_str(str(res["body"]["error"]["code"])).is_equal("MISSING_PARAM")
	# Missing text param on /input/type.
	res = await _http_post("/input/type", {"path": "/root/TypeKeyFixture/TypeRoot/Edit"})
	assert_int(res["code"]).is_equal(400)
	assert_str(str(res["body"]["error"]["code"])).is_equal("MISSING_PARAM")
	# Unknown node on /input/type.
	res = await _http_post("/input/type", {"path": "/root/TypeKeyFixture/Nope", "text": "x"})
	assert_int(res["code"]).is_equal(404)
	assert_str(str(res["body"]["error"]["code"])).is_equal("NODE_NOT_FOUND")
	# Non-Control target on /input/type.
	res = await _http_post("/input/type", {"path": "/root/TypeKeyFixture", "text": "x"})
	assert_int(res["code"]).is_equal(400)
	assert_str(str(res["body"]["error"]["code"])).is_equal("BAD_TARGET")
