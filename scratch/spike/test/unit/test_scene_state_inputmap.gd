extends GdUnitTestSuite
## GTD-015 — scene/state/inputmap read endpoints (SPEC §5.1/§5.8):
## /scene/current, /input/map, /state (+ STATE_AUTOLOAD_MISSING).

const StateScript := preload("res://scratch/spike/test/fixtures/game_state.gd")

var _server: TestDriverServer
var _fixture: Node


func before_test() -> void:
	# Suite node persists across tests — drop the previous fixture.
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.queue_free()
		await get_tree().process_frame
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	_server.stop()
	# The state fixture is added directly under /root — remove it so later
	# suites don't see a stray GameState autoload.
	if _fixture != null and is_instance_valid(_fixture) and _fixture.get_parent() == get_tree().root:
		_fixture.get_parent().remove_child(_fixture)
		_fixture.free()


func _http_get(path: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {}
	http.request_completed.connect(func(_r, code, _headers, body):
		result.code = code
		result.body = body.get_string_from_utf8())
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path])
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


func test_scene_current_no_scene_in_test_env() -> void:
	# The 500 branch fires when tree.current_scene is null. GdUnit used to run
	# without a main scene, but test_reset_isolation (alphabetically earlier)
	# loads one — so force the condition: free the current scene first.
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	assert_that(get_tree().current_scene).is_null()
	var r: Dictionary = await _http_get("/scene/current")
	assert_int(r.get("code", 0)).is_equal(500)
	assert_str(str(_error(r).get("code"))).is_equal("INTERNAL_ERROR")


func test_input_map_shape() -> void:
	# Register a custom action with one key + one mouse event to inspect.
	var action := "gtd015_test_action"
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_ENTER
		key.device = InputEvent.DEVICE_ID_KEYBOARD
		InputMap.action_add_event(action, key)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.device = InputEvent.DEVICE_ID_MOUSE
		InputMap.action_add_event(action, mouse)
	var r: Dictionary = await _http_get("/input/map")
	assert_int(r.get("code", 0)).is_equal(200)
	var actions: Array = _parsed(r).get("data", {}).get("actions", [])
	assert_int(actions.size()).is_greater(0)
	# Find our action.
	var entry: Dictionary = {}
	for a in actions:
		if str(a.get("name")) == action:
			entry = a
			break
	assert_int(entry.size()).is_greater(0)
	var events: Array = entry.get("events", [])
	assert_int(events.size()).is_equal(2)
	# Key event summary.
	var key_ev: Dictionary = events[0]
	assert_str(str(key_ev.get("type"))).is_equal("key")
	assert_int(int(key_ev.get("physical_keycode", -1))).is_equal(KEY_ENTER)
	assert_int(int(key_ev.get("device", -1))).is_equal(InputEvent.DEVICE_ID_KEYBOARD)
	# Mouse event summary.
	var mouse_ev: Dictionary = events[1]
	assert_str(str(mouse_ev.get("type"))).is_equal("mouse_button")
	assert_int(int(mouse_ev.get("button_index", -1))).is_equal(MOUSE_BUTTON_LEFT)
	assert_int(int(mouse_ev.get("device", -1))).is_equal(InputEvent.DEVICE_ID_MOUSE)
	# Built-in actions are present too (ui_accept exists in every project).
	var names: Array = []
	for a in actions:
		names.append(str(a.get("name")))
	assert_bool("ui_accept" in names).is_true()


func test_state_read_and_missing_autoload() -> void:
	# The dev project has no GameState autoload → 409 STATE_AUTOLOAD_MISSING.
	var r: Dictionary = await _http_get("/state")
	assert_int(r.get("code", 0)).is_equal(409)
	var err: Dictionary = _error(r)
	assert_str(str(err.get("code"))).is_equal("STATE_AUTOLOAD_MISSING")
	assert_str(str(err.get("details", {}).get("hint"))).contains("godriver/state_autoload")
	# Add a state autoload fixture → 200 with script-declared properties only.
	# The handler resolves /root/GameState — the fixture must live under root.
	var state: Node = StateScript.new()
	state.name = "GameState"
	_fixture = state
	get_tree().root.add_child(_fixture)
	r = await _http_get("/state")
	assert_int(r.get("code", 0)).is_equal(200)
	var d: Dictionary = _parsed(r).get("data", {})
	assert_str(str(d.get("autoload"))).is_equal("GameState")
	var values: Dictionary = d.get("values", {})
	# Script-declared vars present, serialized per §4.
	assert_int(int(values.get("score", -1))).is_equal(42)
	assert_str(str(values.get("player_name"))).is_equal("hero")
	assert_bool(values.get("hard_mode")).is_false()
	# Engine built-ins excluded.
	assert_that(values.has("name")).is_false()
	assert_that(values.has("position")).is_false()
	assert_that(values.has("process_mode")).is_false()
