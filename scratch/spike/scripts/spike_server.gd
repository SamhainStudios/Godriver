extends Node
## GTD-001 (Spike A1) — vendored godottpd serving /health from a running game.
##
## Dormant unless launched with `--spike` (user args, after `--`).
## Self-test mode: `-- --spike --self-test` runs the A1 check and quits
## with exit code 0 (SPIKE_A1_OK) or 1.

const PORT := 9090
const BIND := "127.0.0.1"
const MAX_BLOCKED_WAITS := 8  # SPEC §6.1 cap
const LONG_POLL_TIMEOUT_MS := 5000

var _server: HttpServer
var _frames := 0
var _input: SpikeInputHandler

# GTD-004: blocked long-poll accounting (SPEC §6.1). Workers increment on
# long-poll start, decrement on completion/timeout; over cap → 503 SERVER_BUSY.
var _blocked_waits := 0
var _wait_mutex := Mutex.new()



func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--spike" in args:
		return
	# GTD-004: keep counting frames (and draining via Dispatcher) while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# GTD-005 headless fix (engine-source verified): under --headless the root
	# Window defaults to 64x64, so Window::_update_mouse_over() treats any
	# pushed event position outside (0,0)-(64,64) as "mouse left the window"
	# and DROPS hover (new_in=false → _mouse_leave_viewport). Hover is the
	# gate for BaseButton presses (status.hovering, base_button.cpp:154).
	# Fix: size the root window from the project settings so synthetic
	# positions resolve inside the visible rect.
	var root := get_tree().root
	root.size = Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", 648)))
	_server = HttpServer.new(true)
	_server.bind_address = BIND
	_server.port = PORT
	_server.register_router(HttpRouter.new("/health", {"get": _handle_health}))
	_server.register_router(HttpRouter.new("/scene/current", {"get": _handle_scene_current}))
	_server.register_router(HttpRouter.new("/wait/long", {"get": _handle_wait_long}))
	_server.register_router(HttpRouter.new("/dev/pause", {"post": _handle_dev_pause}))
	_server.register_router(HttpRouter.new("/node", {"get": _handle_node}))
	_server.register_router(HttpRouter.new("/input/click", {"post": _handle_input_click}))
	add_child(_server)
	_input = SpikeInputHandler.new()
	add_child(_input)
	_server.start()
	print("[spike] server listening on http://%s:%d" % [BIND, PORT])
	if "--self-test" in args:
		_run_self_test()
	elif "--self-test-a2" in args:
		var check := Node.new()
		check.set_script(load("res://scratch/spike/tests/spike_a2_check.gd"))
		add_child(check)
		check.run(self)
	elif "--self-test-a3" in args:
		var check := Node.new()
		check.set_script(load("res://scratch/spike/tests/spike_a3_stress.gd"))
		add_child(check)
		check.run(self)
	elif "--self-test-a4" in args:
		var check := Node.new()
		check.set_script(load("res://scratch/spike/tests/spike_a4_check.gd"))
		add_child(check)
		check.run(self)
	elif "--self-test-c" in args:
		# GTD-006 fixture: build the test_id tree deferred (see GTD-005 note).
		var fixture := Node.new()
		fixture.set_script(load("res://scratch/spike/scripts/test_id_fixture.gd"))
		get_tree().root.add_child.call_deferred(fixture)
		var check := Node.new()
		check.set_script(load("res://scratch/spike/tests/spike_c_check.gd"))
		add_child.call_deferred(check)
		await get_tree().process_frame
		await get_tree().process_frame
		check.run(self)
	elif "--self-test-b" in args:
		# Load the SubViewportContainer fixture alongside the main scene.
		# Deferred: _ready() is still setting up children here.
		var fixture := (load("res://scratch/spike/scenes/sub_viewport_fixture.tscn")
				as PackedScene).instantiate()
		fixture.name = "SubFixture"
		get_tree().root.add_child.call_deferred(fixture)
		var check := Node.new()
		check.set_script(load("res://scratch/spike/tests/spike_b_check.gd"))
		add_child.call_deferred(check)
		# Deferred adds land next frame; then start the check.
		await get_tree().process_frame
		await get_tree().process_frame
		check.run(self)


func _process(_delta: float) -> void:
	_frames += 1


func _handle_health(_req: HttpRequest, res: HttpResponse) -> bool:
	_wait_mutex.lock()
	var blocked := _blocked_waits
	_wait_mutex.unlock()
	res.json(200, {"ok": true, "data": {"status": "ok", "blocked_waits": blocked}})
	return true


## GTD-004: long-poll route — blocks the worker thread until `frames` frames
## have elapsed (or timeout). Blocked-wait accounting per SPEC §6.1: over
## MAX_BLOCKED_WAITS concurrent waits → immediate 503 SERVER_BUSY.
func _handle_wait_long(req: HttpRequest, res: HttpResponse) -> bool:
	_wait_mutex.lock()
	if _blocked_waits >= MAX_BLOCKED_WAITS:
		_wait_mutex.unlock()
		res.json(503, {"ok": false, "error": {"code": "SERVER_BUSY",
				"message": "max_blocked_waits (%d) exceeded" % MAX_BLOCKED_WAITS}})
		return true
	_blocked_waits += 1
	_wait_mutex.unlock()

	# Target is relative to the current frame count (the counter runs from
	# startup, so an absolute target would already be in the past).
	var target_frames: int = _frames + int(req.query.get("frames", 30))
	var deadline := Time.get_ticks_msec() + LONG_POLL_TIMEOUT_MS
	while _frames < target_frames and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)

	_wait_mutex.lock()
	_blocked_waits -= 1
	_wait_mutex.unlock()
	res.json(200, {"ok": true, "data": {"frames": _frames}})
	return true


## GTD-004: pause toggle through the dispatcher (main-thread tree access).
func _handle_dev_pause(req: HttpRequest, res: HttpResponse) -> bool:
	var body: Variant = JSON.parse_string(req.body)
	if typeof(body) != TYPE_DICTIONARY or not body.has("enabled"):
		res.json(400, {"ok": false, "error": {"code": "BAD_REQUEST",
				"message": "body must be {\"enabled\": bool}"}})
		return true
	var enabled: bool = body["enabled"]
	Dispatcher.submit(func() -> void: get_tree().paused = enabled)
	res.json(200, {"ok": true, "data": {"paused": enabled}})
	return true


## GTD-004: node existence check through the dispatcher. Query param form
## (/node?path=/root/Main) — the spike router only matches single segments.
## GTD-006: /node?test_id=x resolves by test_id metadata (SPEC §7):
## 0 matches → 404 NODE_NOT_FOUND; >1 → 409 AMBIGUOUS_MATCH with paths.
func _handle_node(req: HttpRequest, res: HttpResponse) -> bool:
	var test_id: String = str(req.query.get("test_id", ""))
	if test_id != "":
		var matches: Variant = Dispatcher.submit(func() -> Variant:
			return SpikeTestIdLookup.find_all(get_tree().root, test_id))
		if matches.size() == 0:
			res.json(404, {"ok": false, "error": {"code": "NODE_NOT_FOUND",
					"message": "no node with test_id '%s'" % test_id}})
		elif matches.size() > 1:
			res.json(409, {"ok": false, "error": {"code": "AMBIGUOUS_MATCH",
					"message": "%d nodes share test_id '%s'" % [matches.size(), test_id],
					"details": {"matching_paths": matches}}})
		else:
			res.json(200, {"ok": true, "data": {"test_id": test_id,
					"path": matches[0]}})
		return true

	var node_path: String = str(req.query.get("path", ""))
	if node_path == "":
		res.json(400, {"ok": false, "error": {"code": "BAD_REQUEST",
				"message": "missing ?path= or ?test_id="}})
		return true
	var exists: Variant = Dispatcher.submit(func() -> Variant:
		return get_tree().root.get_node_or_null(NodePath(node_path)) != null)
	if exists:
		res.json(200, {"ok": true, "data": {"path": node_path, "exists": true}})
	else:
		res.json(404, {"ok": false, "error": {"code": "NODE_NOT_FOUND",
				"message": "no node at %s" % node_path}})
	return true


## GTD-005 (Spike B): click injection. Body {"path": "/root/Main/Button"}.
## The whole injection must run on the main thread → marshal through the
## Dispatcher. 200 = injected (NOT processed — SPEC §6 timing contract).
func _handle_input_click(req: HttpRequest, res: HttpResponse) -> bool:
	var body: Variant = JSON.parse_string(req.body)
	if typeof(body) != TYPE_DICTIONARY or not body.has("path"):
		res.json(400, {"ok": false, "error": {"code": "BAD_REQUEST",
				"message": "body must be {\"path\": \"/root/...\"}"}})
		return true
	var node_path: String = body["path"]
	var err: Variant = Dispatcher.submit(func() -> Variant:
		return _input.click_at(node_path))
	if err == "":
		res.json(200, {"ok": true, "data": {"injected": true, "path": node_path}})
	else:
		res.json(404, {"ok": false, "error": {"code": "NODE_NOT_FOUND",
				"message": str(err)}})
	return true


## GTD-002: worker-thread handler marshals the scene query through the
## Dispatcher so the SceneTree access happens on the main thread.
func _handle_scene_current(_req: HttpRequest, res: HttpResponse) -> bool:
	var scene_name: Variant = Dispatcher.submit(func() -> Variant:
		return get_tree().current_scene.name)
	res.json(200, {"ok": true, "data": {"scene": scene_name}})
	return true


func get_main_thread_id() -> int:
	return Dispatcher._main_id


func _run_self_test() -> void:
	var err := await _query("/health")
	if err != OK:
		push_error("[spike] FAIL: health query failed (%s)" % err)
		get_tree().quit(1)
		return
	# Frame-rate sanity while serving: 60 sequential requests, count frames elapsed.
	var frames_before := _frames
	for i in range(60):
		err = await _query("/health")
		if err != OK:
			push_error("[spike] FAIL: request %d failed (%s)" % [i, err])
			get_tree().quit(1)
			return
	var frames_elapsed := _frames - frames_before
	print("[spike] frames elapsed during 60 sequential requests: %d" % frames_elapsed)
	if frames_elapsed < 30:
		push_error("[spike] FAIL: main loop starved while serving (%d frames)" % frames_elapsed)
		get_tree().quit(1)
		return
	print("SPIKE_A1_OK")
	get_tree().quit(0)


## One GET request; returns OK on a 200 with a valid {ok:true} envelope, else ERR.
func _query(path: String) -> int:
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var err := http.request("http://%s:%d%s" % [BIND, PORT, path])
	if err != OK:
		http.queue_free()
		return err
	var result: Array = await http.request_completed
	http.queue_free()
	var req_result: int = result[0]
	var code: int = result[1]
	var body: PackedByteArray = result[3]
	if req_result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("[spike] bad response: result=%s code=%d" % [req_result, code])
		return ERR_QUERY_FAILED
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.get("ok", false):
		push_error("[spike] bad envelope: %s" % [parsed])
		return ERR_QUERY_FAILED
	return OK
