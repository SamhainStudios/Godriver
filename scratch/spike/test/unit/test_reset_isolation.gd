extends GdUnitTestSuite
## GTD-016 — atomic /reset (SPEC §5.0): isolation (orphan/tween/time_scale/
## pause/state), atomicity (200 only after ready), 504 on a blocking scene,
## tween_mode handling.

const GameStateScript := preload("res://scratch/spike/test/fixtures/game_state.gd")

var _server: TestDriverServer
var _state_fixture: Node


func before_test() -> void:
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	# The reset test pauses the tree — the server (and its dispatcher child)
	# must keep polling/draining while paused.
	_server.process_mode = Node.PROCESS_MODE_ALWAYS
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()
	# Protect the GdUnit runner chain from the orphan sweep: whatever node of
	# ours sits directly under /root must carry the KEEP_META escape hatch.
	var top: Node = self
	while top.get_parent() != null and top.get_parent() != get_tree().root:
		top = top.get_parent()
	if top.get_parent() == get_tree().root:
		top.set_meta(TestDriverSceneHandler.KEEP_META, true)
	# State autoload fixture directly under /root (handler resolves
	# /root/<name>); KEEP_META so the orphan sweep doesn't free it mid-suite.
	if _state_fixture != null and is_instance_valid(_state_fixture):
		_state_fixture.get_parent().remove_child(_state_fixture)
		_state_fixture.free()
	_state_fixture = GameStateScript.new()
	_state_fixture.name = "GameState"
	_state_fixture.set_meta(TestDriverSceneHandler.KEEP_META, true)
	get_tree().root.add_child(_state_fixture)


func after_test() -> void:
	_server.stop()
	if _state_fixture != null and is_instance_valid(_state_fixture):
		_state_fixture.get_parent().remove_child(_state_fixture)
		_state_fixture.free()


func _http_post(path: String, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {}
	http.request_completed.connect(func(_r, code, _headers, b):
		result.code = code
		result.body = b.get_string_from_utf8())
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], [], HTTPClient.METHOD_POST, body)
	var waited := 0
	while not result.has("code") and waited < 600:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func _parsed(r: Dictionary) -> Dictionary:
	return JSON.parse_string(r.body)


func _error(r: Dictionary) -> Dictionary:
	return _parsed(r).get("error", {})


func test_reset_isolation_full() -> void:
	# Dirty the world: time_scale, pause, an orphan under /root, a tree tween,
	# and a mutated state autoload.
	Engine.time_scale = 5.0
	get_tree().paused = true
	var orphan := Node.new()
	orphan.name = "Gtd016Orphan"
	get_tree().root.add_child(orphan)
	var tween := get_tree().create_tween()
	tween.tween_interval(10.0)
	_state_fixture.score = 99
	# POST /reset — must complete even though the tree is paused (dispatcher
	# PROCESS_MODE_ALWAYS) and answer 200 only once the scene is ready.
	var r: Dictionary = await _http_post("/reset", "{}")
	assert_int(r.get("code", 0)).is_equal(200)
	var d: Dictionary = _parsed(r).get("data", {})
	assert_str(str(d.get("reloaded_scene"))).is_equal("res://scratch/spike/scenes/main.tscn")
	assert_bool(d.get("scene_ready", false)).is_true()
	# Deferred teardown — give queue_free a frame.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(orphan)).is_false()
	assert_int(get_tree().get_processed_tweens().size()).is_equal(0)
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_bool(get_tree().paused).is_false()
	assert_that(get_tree().current_scene).is_not_null()
	assert_str(str(get_tree().current_scene.name)).is_equal("Main")
	# State autoload reset to script-declared initial values.
	assert_int(int(_state_fixture.score)).is_equal(42)


func test_reset_async_ready_caveat() -> void:
	# DOCUMENTED CAVEAT (verified against engine behavior): is_node_ready()
	# becomes true when NOTIFICATION_READY fires — BEFORE a suspended
	# script _ready() concludes. A scene whose _ready() awaits forever
	# therefore still yields a 200 reset; /reset cannot detect async init
	# (games with async init must expose a readiness signal, SPEC §5.0).
	# The 504 SCENE_READY_TIMEOUT path stays defensive (engine hang / scene
	# never appearing) and is not reachable from a suspended _ready().
	var original: String = ProjectSettings.get_setting("application/run/main_scene", "")
	ProjectSettings.set_setting("application/run/main_scene", "res://scratch/spike/test/fixtures/blocking_scene.tscn")
	var r: Dictionary = await _http_post("/reset", "{}")
	# Restore BEFORE asserting so a failure doesn't poison later tests.
	ProjectSettings.set_setting("application/run/main_scene", original)
	assert_int(r.get("code", 0)).is_equal(200)
	assert_str(str(get_tree().current_scene.name)).is_equal("BlockingScene")
	# Recovery: a normal reset brings the real main scene back.
	r = await _http_post("/reset", "{}")
	assert_int(r.get("code", 0)).is_equal(200)
	assert_str(str(get_tree().current_scene.name)).is_equal("Main")


func test_reset_tween_modes() -> void:
	# Invalid tween_mode → 400 TYPE_MISMATCH.
	var r: Dictionary = await _http_post("/reset", "{\"tween_mode\": \"bogus\"}")
	assert_int(r.get("code", 0)).is_equal(400)
	assert_str(str(_error(r).get("code"))).is_equal("TYPE_MISMATCH")
	# "await" mode: a short tween completes before the reset resolves.
	var tween := get_tree().create_tween()
	tween.tween_interval(0.2)
	r = await _http_post("/reset", "{\"tween_mode\": \"await\"}")
	assert_int(r.get("code", 0)).is_equal(200)
	assert_int(get_tree().get_processed_tweens().size()).is_equal(0)
