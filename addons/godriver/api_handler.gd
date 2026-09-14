class_name TestDriverApi
extends Node
## GTD-011/012 — route handlers + dispatch funnel.
##
## godottpd calls handlers on WORKER threads. Every request is marshaled
## through TestDriverDispatcher.submit() so all SceneTree/node access happens
## on the main thread. Worker threads only do thread-safe work: auth header
## scan and plain-data extraction (strings/numbers) from the request.
##
## Handler contract: a route maps to a `_main_<name>` method on this node.
## `_main_*` methods run on the main thread, receive one Dictionary of
## extracted plain-data args, and MUST return {"code": int, "body": Dictionary}.
## A handler that crashes (script error → null result) or returns anything
## else is funneled to a 500 INTERNAL_ERROR envelope — the server stays up.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


const TestDriverAssertionHandler := preload("res://addons/godriver/handlers/assertion_handler.gd")
const TestDriverScreenshotHandler := preload("res://addons/godriver/handlers/screenshot_handler.gd")
const TestDriverWindowHandler := preload("res://addons/godriver/handlers/window_handler.gd")

const SPEC_VERSION := "0.1"

## When non-empty, requests must carry `Authorization: Bearer <token>`;
## otherwise 401 UNAUTHORIZED (SPEC Appendix A).
var token := ""

## The main-thread task queue (GTD-012). Set by TestDriverServer.setup().
var dispatcher: TestDriverDispatcher

## Handler registration map: path -> {http_method: handler_name}.
## handler_name refers to a `_main_<name>` method on this node.
## A path starting with "^" is compiled as a RAW REGEX by godottpd
## (http_server.gd register_router) — used for multi-segment node paths;
## named groups are read from request.query_match in _extract_args.
var routes := {
	"/health": {"get": "health"},
	# Plain "/node" (query-param form: /node?test_id=x) — GTD-014.
	"/node": {"get": "node_query"},
	# Raw-regex route for /node/<path> and /node/<path>/property/<name> — GTD-013.
	"^/node/(?<npath>.+?)[/#?]?$": {"get": "node"},
	# GTD-025: /ui/layout — plain form (test_id query) + raw-regex path form.
	"/ui/layout": {"get": "ui_layout"},
	"^/ui/layout/(?<npath>.+?)[/#?]?$": {"get": "ui_layout"},
	"/nodes": {"get": "nodes"},
	# GTD-015 read endpoints (SPEC §5.1/§5.8).
	"/scene/current": {"get": "scene_current"},
	"/input/map": {"get": "input_map"},
	# GTD-020: POST /input/click (SPEC §5.3).
	"/input/click": {"post": "input_click"},
	# GTD-021: POST /input/type + /input/key (SPEC §5.3).
	"/input/type": {"post": "input_type"},
	"/input/key": {"post": "input_key"},
	# GTD-054: key down/up split (held-key testing).
	"/input/key_down": {"post": "input_key_down"},
	"/input/key_up": {"post": "input_key_up"},
	"/state": {"get": "state"},
	"/state/schema": {"get": "state_schema", "post": "state_schema"},
	"/state/set": {"post": "state_set"},
	# GTD-024: GET /assets/loaded (SPEC §5.9a).
	"/assets/loaded": {"get": "assets_loaded"},
	# GTD-016: /reset is ASYNC (main-thread coroutine + worker-side slot
	# polling) — dispatched through _dispatch_reset, not the sync funnel.
	"/reset": {"post": "reset"},
	# GTD-023: /scene/load is ASYNC like /reset — same slot-polling machinery,
	# and the in-flight guard is SHARED (a load and a reset must not interleave).
	"/scene/load": {"post": "scene_load"},
	# GTD-026: GET /wait/frames?frames=N (SPEC §5.7) — long-poll; the worker
	# blocks until N process_frames elapse (pause-safe; never timers/sleeps).
	"/wait/frames": {"get": "wait_frames"},
	# POST /wait/tween (Issue #8) — async wait for all SceneTree tweens to complete.
	"/wait/tween": {"post": "wait_tween"},
	# GTD-031: /signal/watch, /signal/poll, /signal/wait (SPEC §5.5).
	"/signal/watch": {"post": "signal_watch"},
	"/signal/poll": {"get": "signal_poll", "post": "signal_poll"},
	"/signal/wait": {"get": "signal_wait", "post": "signal_wait"},
	# GTD-032: /assert/visible, /assert/enabled, /assert/property (SPEC §5.6).
	"/assert/visible": {"post": "assert_visible"},
	"/assert/enabled": {"post": "assert_enabled"},
	"/assert/property": {"post": "assert_property"},
	# GTD-034: /dev/seed, /dev/time_scale, /dev/pause, /dev/save/load (SPEC §5.9).
	"/dev/seed": {"post": "dev_seed"},
	"/dev/time_scale": {"post": "dev_time_scale"},
	"/dev/pause": {"post": "dev_pause"},
	"/dev/save/load": {"post": "dev_save_load"},
	# GTD-050: /screenshot/capture, /screenshot/region (SPEC §5.10).
	"/screenshot/capture": {"get": "screenshot_capture", "post": "screenshot_capture"},
	"/screenshot/region": {"get": "screenshot_region", "post": "screenshot_region"},
	# GTD-053: /window/resize, /window/state (SPEC §5.10).
	"/window/resize": {"post": "window_resize"},
	"/window/state": {"get": "window_state"},
}

# --- /wait/frames state (GTD-026, SPEC §5.7) ---

## Main-loop frame counter, incremented in _process. Workers read it to
## detect frame advancement (relative targets — GTD-004 finding).
var _frames := 0
## Long-poll concurrency cap (SPEC §6.1): Mutex-guarded count of workers
## currently blocked in /wait/frames; over the cap → 503 SERVER_BUSY.
const MAX_BLOCKED_WAITS := 8
static var _blocked_waits := 0
static var _blocked_waits_mutex := Mutex.new()


func _process(_delta: float) -> void:
	_frames += 1

## Reset serialization guard: only one /reset coroutine may run at a time.
## Main-thread-only access (set in _start_reset, cleared in its done callback).
var _reset_in_flight := false


func _authorized(req: HttpRequest) -> bool:
	if token.is_empty():
		return true
	# godottpd stores headers verbatim (mixed case possible) — scan
	# case-insensitively.
	for key in req.headers:
		if String(key).to_lower() == "authorization":
			return String(req.headers[key]) == "Bearer " + token
	return false


## Extract plain data (strings/numbers) from the request ON THE WORKER THREAD.
## The resulting Dictionary is what the main-thread handler receives — never
## pass godottpd objects (HttpRequest/HttpResponse) across the queue.
func _extract_args(handler_name: String, req: HttpRequest) -> Dictionary:
	match handler_name:
		"node":
			# Raw-regex route: node path (and optional /property/<name>) comes
			# from the named group; percent-decoding happens on the main thread.
			var npath := ""
			if req.query_match != null:
				npath = req.query_match.get_string("npath")
			return {"npath": npath}
		"node_query":
			# godottpd auto-converts numeric query values ("123" → int) —
			# str() everything so test_ids stay strings.
			return {"test_id": str(req.query.get("test_id", ""))}
		"ui_layout":
			# Both forms: raw-regex path group OR test_id query + depth.
			var upath := ""
			if req.query_match != null:
				upath = req.query_match.get_string("npath")
			return {
				"npath": upath,
				"test_id": str(req.query.get("test_id", "")),
				"depth": req.query.get("depth", 0),
			}
		"nodes", "assets_loaded":
			return {
				"group": str(req.query.get("group", "")),
				"limit": req.query.get("limit", 100),
				"offset": req.query.get("offset", 0),
			}
		"wait_frames":
			return {"frames": req.query.get("frames", 1)}
		"input_click", "input_type", "input_key", "input_key_down", "input_key_up", "signal_watch", "signal_poll", "signal_wait", "assert_visible", "assert_enabled", "assert_property", "state", "state_schema", "state_set", "dev_seed", "dev_time_scale", "dev_pause", "dev_save_load", "screenshot_capture", "screenshot_region", "window_resize":
			var res_dict := {}
			var body: Variant = req.get_body_parsed()
			if not (body is Dictionary) and not String(req.body).is_empty():
				body = JSON.parse_string(String(req.body))
			if body is Dictionary:
				for k in body:
					res_dict[k] = body[k]
			for k in req.query:
				res_dict[k] = req.query[k]
			return res_dict
		_:
			return {}


## Worker-thread entry point wired into godottpd routers by
## TestDriverServer.register_routes(). Auth check happens here (thread-safe
## string ops); the handler runs on the main thread via the dispatcher.
func dispatch(handler_name: String, req: HttpRequest, res: HttpResponse) -> bool:
	if not _authorized(req):
		res.json(401, {"ok": false, "error": {"code": "UNAUTHORIZED", "message": "missing or invalid bearer token"}})
		return true
	if handler_name == "reset":
		return _dispatch_reset(req, res)
	if handler_name == "scene_load":
		return _dispatch_scene_load(req, res)
	if handler_name == "wait_frames":
		return _dispatch_wait_frames(req, res)
	if handler_name == "wait_tween":
		return _dispatch_wait_tween(req, res)
	if handler_name == "signal_wait":
		return _dispatch_signal_wait(req, res)
	var args := _extract_args(handler_name, req)
	var result: Variant = dispatcher.submit(Callable(self, "_main_" + handler_name).bind(args))
	if result is Dictionary and result.has("code"):
		var code := int(result.code)
		if result.has("raw") and result.raw is PackedByteArray:
			var content_type: String = result.get("content_type", "image/png")
			if result.has("headers") and result.headers is Dictionary:
				for h in result.headers:
					res.headers[StringName(h)] = result.headers[h]
			res.send_raw(code, result.raw, content_type)
		elif result.has("body"):
			res.json(code, result.body)
		else:
			res.json(500, {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "handler returned empty body"}})
	else:
		# Error funnel: handler crashed (script error → null) or returned
		# malformed data. Respond 500; the server stays up.
		res.json(500, {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "handler crashed or returned malformed data"}})
	return true


# --- main-thread handlers (return {code, body}) ---

func _main_health(_args: Dictionary) -> Dictionary:
	var v := Engine.get_version_info()
	var godot_version := "%d.%d.%d" % [v.major, v.minor, v.patch]
	return {
		"code": 200,
		"body": {"ok": true, "data": {"status": "ok", "godot_version": godot_version, "spec_version": SPEC_VERSION}},
	}


## Test hook (GTD-012): returns null — a malformed handler result — to
## exercise the 500 INTERNAL_ERROR funnel without real error spam.
func _main_boom(_args: Dictionary) -> Variant:
	return null


## GET /node/<path> and GET /node/<path>/property/<name> (GTD-013, SPEC §5.2).
## One raw-regex route serves both forms: the path is split at the LAST
## "/property/" — a trailing segment after it means a property read.
## Edge case: a node literally named "property" as the second-to-last segment
## is ambiguous; prefer test_id queries (GTD-014) for such trees.
func _main_node(args: Dictionary) -> Dictionary:
	var npath: String = args.get("npath", "")
	var root := get_tree().root
	var idx := npath.rfind("/property/")
	if idx >= 0 and idx + 10 < npath.length():
		return TestDriverNodeHandler.get_property(root, npath.substr(0, idx), npath.substr(idx + 10))
	return TestDriverNodeHandler.get_info(root, npath)


## GET /node?test_id=<id> (GTD-014, SPEC §5.2/§7).
func _main_node_query(args: Dictionary) -> Dictionary:
	var test_id: String = args.get("test_id", "")
	if test_id.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "required query parameter 'test_id' is absent"}},
		}
	return TestDriverNodeHandler.find_by_test_id(get_tree().root, test_id)


## GET /nodes?group=<name> (GTD-014, SPEC §5.2). limit 1..1000, offset >= 0.
func _main_nodes(args: Dictionary) -> Dictionary:
	var group: String = args.get("group", "")
	if group.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "required query parameter 'group' is absent"}},
		}
	var limit_v: Variant = args.get("limit", 100)
	var offset_v: Variant = args.get("offset", 0)
	# godottpd may deliver limit/offset as int, float, or string depending on
	# the query text — coerce defensively; anything non-numeric is a type error.
	var limit := -1
	if limit_v is int:
		limit = limit_v
	elif limit_v is float and is_equal_approx(limit_v, float(int(limit_v))):
		limit = int(limit_v)
	elif limit_v is String and limit_v.is_valid_int():
		limit = int(limit_v)
	if limit < 1 or limit > 1000:
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "TYPE_MISMATCH", "message": "limit must be an integer in 1..1000", "details": {"expected": "1..1000", "got": str(limit_v)}}},
		}
	var offset := 0
	if offset_v is int:
		offset = offset_v
	elif offset_v is float and is_equal_approx(offset_v, float(int(offset_v))):
		offset = int(offset_v)
	elif offset_v is String and offset_v.is_valid_int():
		offset = int(offset_v)
	return TestDriverNodeHandler.list_group(get_tree().root, group, limit, offset)


## GET /scene/current (GTD-015, SPEC §5.1).
func _main_scene_current(_args: Dictionary) -> Dictionary:
	return TestDriverSceneHandler.current(get_tree())


## GET /input/map (GTD-015, SPEC §5.1).
func _main_input_map(_args: Dictionary) -> Dictionary:
	return TestDriverInputHandler.input_map()


## POST /input/click (GTD-020, SPEC §5.3/§6) — 200 = injected only.
func _main_input_click(args: Dictionary) -> Dictionary:
	return TestDriverInputHandler.click(get_tree(), args)


## POST /input/type (GTD-021, SPEC §5.3/§6) — 200 = injected only.
func _main_input_type(args: Dictionary) -> Dictionary:
	return TestDriverInputHandler.type_text(get_tree(), args)


## POST /input/key (GTD-021, SPEC §5.3/§6) — 200 = injected only.
func _main_input_key(args: Dictionary) -> Dictionary:
	return TestDriverInputHandler.key(get_tree(), args)


## POST /input/key_down + /input/key_up (GTD-054, SPEC §5.3) - held-key split.
func _main_input_key_down(args: Dictionary) -> Dictionary:
	return TestDriverInputHandler.key_down(get_tree(), args)


func _main_input_key_up(args: Dictionary) -> Dictionary:
	return TestDriverInputHandler.key_up(get_tree(), args)


## GET /state (GTD-015/033, SPEC §5.8).
func _main_state(args: Dictionary) -> Dictionary:
	return TestDriverStateHandler.read_state(get_tree(), args)


## GET/POST /state/schema (GTD-033, SPEC §5.8).
func _main_state_schema(args: Dictionary) -> Dictionary:
	return TestDriverStateHandler.get_schema(get_tree(), args)


## POST /state/set (GTD-033, SPEC §5.8/§8).
func _main_state_set(args: Dictionary) -> Dictionary:
	return TestDriverStateHandler.set_state(get_tree(), args)


## POST /dev/seed (GTD-034, SPEC §5.9/§9).
func _main_dev_seed(args: Dictionary) -> Dictionary:
	return TestDriverDevHandler.seed_rng(args)


## POST /dev/time_scale (GTD-034, SPEC §5.9/§9).
func _main_dev_time_scale(args: Dictionary) -> Dictionary:
	return TestDriverDevHandler.set_time_scale(args)


## POST /dev/pause (GTD-034, SPEC §5.9/§9).
func _main_dev_pause(args: Dictionary) -> Dictionary:
	return TestDriverDevHandler.set_pause(get_tree(), args)


## POST /dev/save/load (GTD-034, SPEC §5.9/§9).
func _main_dev_save_load(args: Dictionary) -> Dictionary:
	return TestDriverDevHandler.save_load(args)


## GET /assets/loaded (GTD-024, SPEC §5.9a).
func _main_assets_loaded(args: Dictionary) -> Dictionary:
	return TestDriverAssetsHandler.loaded(get_tree(), int(args.get("limit", 100)), int(args.get("offset", 0)))


## GET /ui/layout/<path> or /ui/layout?test_id= (GTD-025, SPEC §5.1).
func _main_ui_layout(args: Dictionary) -> Dictionary:
	# Raw-regex path form → the resolve_target "path" arg.
	var a := Dictionary(args)
	var npath := str(a.get("npath", ""))
	if not npath.is_empty() and a.get("path", "") == "":
		a["path"] = npath
	a.erase("npath")
	return TestDriverUiHandler.get_layout(get_tree(), a)


# --- /wait/frames (GTD-026, SPEC §5.7) — long-poll on the worker ---

## Worker-thread entry for GET /wait/frames?frames=N. The worker BLOCKS until
## N process_frames elapse (frame counter advanced by _process on the main
## thread — pause-safe, never timers/sleeps). Relative target (GTD-004
## finding: the counter runs from startup, so absolute targets are already
## past). Concurrency capped at MAX_BLOCKED_WAITS → 503 SERVER_BUSY (§6.1).
func _dispatch_wait_frames(req: HttpRequest, res: HttpResponse) -> bool:
	var frames := int(req.query.get("frames", 1))
	if frames < 1 or frames > 600:
		res.json(400, {"ok": false, "error": {"code": "TYPE_MISMATCH", "message": "frames must be within 1..600", "details": {"expected": "1..600", "got": frames}}})
		return true
	_blocked_waits_mutex.lock()
	if _blocked_waits >= MAX_BLOCKED_WAITS:
		_blocked_waits_mutex.unlock()
		res.json(503, {"ok": false, "error": {"code": "SERVER_BUSY", "message": "too many concurrent long-polls (cap %d)" % MAX_BLOCKED_WAITS}})
		return true
	_blocked_waits += 1
	_blocked_waits_mutex.unlock()
	var target := _frames + frames
	var deadline := Time.get_ticks_msec() + 5000
	while _frames < target:
		if Time.get_ticks_msec() > deadline:
			_blocked_waits_mutex.lock()
			_blocked_waits -= 1
			_blocked_waits_mutex.unlock()
			res.json(504, {"ok": false, "error": {"code": "SCENE_READY_TIMEOUT", "message": "frame wait exceeded 5s (engine stalled?)"}})
			return true
		OS.delay_msec(5)
	_blocked_waits_mutex.lock()
	_blocked_waits -= 1
	_blocked_waits_mutex.unlock()
	res.json(200, {"ok": true, "data": {"waited": frames}})
	return true


# --- /reset (GTD-016, SPEC §5.0) — async dispatch ---

## Worker-thread entry for POST /reset. The reset sequence awaits frames, so
## it CANNOT run inside the synchronous dispatcher funnel (the main thread
## must keep ticking for process_frame to fire). Instead:
##   1. worker submits a fast SYNC start-task → starts the reset coroutine
##      on the main thread and returns immediately;
##   2. worker polls a Mutex-guarded slot (bounded 15s — well above the 5s
##      readiness bound) until the coroutine fills it.
## A crashed coroutine therefore cannot hang the worker forever: the poll
## deadline fires and the funnel responds 500.
func _dispatch_reset(req: HttpRequest, res: HttpResponse) -> bool:
	var tween_mode := "kill"
	var body: Variant = req.get_body_parsed()
	if not (body is Dictionary) and not String(req.body).is_empty():
		# get_body_parsed() needs a JSON content-type; fall back to parsing
		# the raw body so clients that omit the header still work.
		body = JSON.parse_string(String(req.body))
	if body is Dictionary:
		tween_mode = str(body.get("tween_mode", "kill"))
	if tween_mode != "kill" and tween_mode != "await":
		res.json(400, {"ok": false, "error": {"code": "TYPE_MISMATCH", "message": "tween_mode must be 'kill' or 'await'", "details": {"expected": "kill|await", "got": tween_mode}}})
		return true
	var slot := {"done": false, "result": null}
	var slot_mutex := Mutex.new()
	var start_result: Variant = dispatcher.submit(Callable(self, "_start_reset").bind(tween_mode, slot, slot_mutex))
	if start_result is Dictionary and start_result.has("code") and int(start_result.code) != 200:
		# Synchronous start failure — funnel it directly.
		res.json(int(start_result.code), start_result.body)
		return true
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		slot_mutex.lock()
		var done: bool = slot.done
		var result: Variant = slot.result
		slot_mutex.unlock()
		if done:
			if result is Dictionary and result.has("code") and result.has("body"):
				res.json(int(result.code), result.body)
			else:
				res.json(500, {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "reset coroutine crashed or returned malformed data"}})
			return true
		OS.delay_msec(25)
	res.json(504, {"ok": false, "error": {"code": "SCENE_READY_TIMEOUT", "message": "reset exceeded the worker wait bound (15s)"}})
	return true


## Main-thread sync start-task: launches the reset coroutine and returns at
## once (the coroutine continues across frames and completes the slot).
func _start_reset(tween_mode: String, slot: Dictionary, slot_mutex: Mutex) -> Dictionary:
	if _reset_in_flight:
		return {
			"code": 503,
			"body": {"ok": false, "error": {"code": "SERVER_BUSY", "message": "another /reset is already in flight"}},
		}
	_reset_in_flight = true
	# Lambdas capture locals by value, but Dictionary/Mutex are reference
	# types — mutating slot's CONTENTS here is visible to the polling worker.
	TestDriverSceneHandler.reset(get_tree(), tween_mode, func(result: Variant):
		_reset_in_flight = false
		slot_mutex.lock()
		slot.done = true
		slot.result = result
		slot_mutex.unlock())
	return {"code": 200, "body": {}}


# --- /scene/load (GTD-023, SPEC §5.0) — async dispatch, shared guard ---

## Worker-thread entry for POST /scene/load. Mirrors _dispatch_reset exactly
## (same slot-polling machinery, same 15s worker bound) except the body is
## {"path": ...} and the start-task launches load_scene. The in-flight guard
## (_reset_in_flight) is SHARED with /reset: a load and a reset must never
## interleave (both mutate current_scene).
func _dispatch_scene_load(req: HttpRequest, res: HttpResponse) -> bool:
	var path := ""
	var tween_mode := "none"
	var body: Variant = req.get_body_parsed()
	if not (body is Dictionary) and not String(req.body).is_empty():
		body = JSON.parse_string(String(req.body))
	if body is Dictionary:
		path = str(body.get("path", ""))
		tween_mode = str(body.get("tween_mode", "none"))
	var slot := {"done": false, "result": null}
	var slot_mutex := Mutex.new()
	var start_result: Variant = dispatcher.submit(Callable(self, "_start_scene_load").bind(path, tween_mode, slot, slot_mutex))
	if start_result is Dictionary and start_result.has("code") and int(start_result.code) != 200:
		res.json(int(start_result.code), start_result.body)
		return true
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		slot_mutex.lock()
		var done: bool = slot.done
		var result: Variant = slot.result
		slot_mutex.unlock()
		if done:
			if result is Dictionary and result.has("code") and result.has("body"):
				res.json(int(result.code), result.body)
			else:
				res.json(500, {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "scene/load coroutine crashed or returned malformed data"}})
			return true
		OS.delay_msec(25)
	res.json(504, {"ok": false, "error": {"code": "SCENE_READY_TIMEOUT", "message": "scene/load exceeded the worker wait bound (15s)"}})
	return true


## Main-thread sync start-task (same contract as _start_reset; shared guard).
func _start_scene_load(path: String, tween_mode: String, slot: Dictionary, slot_mutex: Mutex) -> Dictionary:
	if _reset_in_flight:
		return {
			"code": 503,
			"body": {"ok": false, "error": {"code": "SERVER_BUSY", "message": "another /reset or /scene/load is already in flight"}},
		}
	_reset_in_flight = true
	TestDriverSceneHandler.load_scene(get_tree(), path, func(result: Variant):
		_reset_in_flight = false
		slot_mutex.lock()
		slot.done = true
		slot.result = result
		slot_mutex.unlock(), tween_mode)
	return {"code": 200, "body": {}}


# --- /wait/tween (Issue #8) — async dispatch ---

## Worker-thread entry for POST /wait/tween. Waits for all SceneTree tweens
## to finish on the main thread, or returns 504 on timeout.
func _dispatch_wait_tween(req: HttpRequest, res: HttpResponse) -> bool:
	var timeout_ms := 5000
	var body: Variant = req.get_body_parsed()
	if not (body is Dictionary) and not String(req.body).is_empty():
		body = JSON.parse_string(String(req.body))
	if body is Dictionary and body.has("timeout"):
		timeout_ms = int(body["timeout"])
	var slot := {"done": false, "result": null}
	var slot_mutex := Mutex.new()
	var start_result: Variant = dispatcher.submit(Callable(self, "_start_wait_tween").bind(timeout_ms, slot, slot_mutex))
	if start_result is Dictionary and start_result.has("code") and int(start_result.code) != 200:
		res.json(int(start_result.code), start_result.body)
		return true
	var deadline := Time.get_ticks_msec() + timeout_ms + 2000
	while Time.get_ticks_msec() < deadline:
		slot_mutex.lock()
		var done: bool = slot.done
		var result: Variant = slot.result
		slot_mutex.unlock()
		if done:
			if result is Dictionary and result.has("code") and result.has("body"):
				res.json(int(result.code), result.body)
			else:
				res.json(500, {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "wait/tween coroutine crashed or returned malformed data"}})
			return true
		OS.delay_msec(25)
	res.json(504, {"ok": false, "error": {"code": "TWEEN_TIMEOUT", "message": "wait/tween exceeded the wait bound (%dms)" % timeout_ms}})
	return true


func _start_wait_tween(timeout_ms: int, slot: Dictionary, slot_mutex: Mutex) -> Dictionary:
	TestDriverSceneHandler.wait_tweens(get_tree(), timeout_ms, func(result: Variant):
		slot_mutex.lock()
		slot.done = true
		slot.result = result
		slot_mutex.unlock())
	return {"code": 200, "body": {}}


# --- GTD-031 Signal Endpoints (SPEC §5.5) ---

func _main_signal_watch(args: Dictionary) -> Dictionary:
	return TestDriverSignalHandler.watch(get_tree(), args)


func _main_signal_poll(args: Dictionary) -> Dictionary:
	return TestDriverSignalHandler.poll(args)


func _dispatch_signal_wait(req: HttpRequest, res: HttpResponse) -> bool:
	var args := _extract_args("signal_wait", req)
	var signal_name := str(args.get("signal", ""))
	if signal_name.is_empty():
		res.json(400, {"ok": false, "error": {"code": "MISSING_PARAM", "message": "missing required parameter 'signal'"}})
		return true

	var target_path := str(args.get("path", ""))
	var test_id := str(args.get("test_id", ""))

	# If target_path is missing but test_id is present, resolve it on the main thread
	if target_path.is_empty() and not test_id.is_empty():
		var resolved: Variant = dispatcher.submit(Callable(TestDriverInputHandler, "resolve_target").bind(get_tree().root, args))
		if resolved is Dictionary:
			if not resolved.get("ok", false):
				res.json(int(resolved.get("code", 400)), {"ok": false, "error": resolved.get("error", {})})
				return true
			target_path = str(resolved.get("path", ""))

	_blocked_waits_mutex.lock()
	if _blocked_waits >= MAX_BLOCKED_WAITS:
		_blocked_waits_mutex.unlock()
		res.json(503, {"ok": false, "error": {"code": "SERVER_BUSY", "message": "max blocked waits (%d) reached" % MAX_BLOCKED_WAITS}})
		return true
	_blocked_waits += 1
	_blocked_waits_mutex.unlock()

	var min_seq := TestDriverSignalHandler.get_current_seq()
	var timeout_sec := float(args.get("timeout", 5.0))
	if timeout_sec <= 0.0:
		timeout_sec = 5.0
	if timeout_sec > 30.0:
		timeout_sec = 30.0

	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var final_status := {"code": 200, "body": {"ok": true, "data": {"signaled": false, "timed_out": true}}}

	while Time.get_ticks_msec() < deadline:
		var st := TestDriverSignalHandler.check_wait_status(target_path, signal_name, min_seq)
		if st.get("status", "") == "found":
			final_status = {
				"code": 200,
				"body": {"ok": true, "data": {"signaled": true, "emission": st.get("emission")}}
			}
			break
		elif st.get("status", "") == "reset":
			final_status = {
				"code": 200,
				"body": {"ok": true, "data": {"signaled": false, "reset": true}}
			}
			break
		OS.delay_msec(25)

	_blocked_waits_mutex.lock()
	_blocked_waits -= 1
	_blocked_waits_mutex.unlock()

	res.json(int(final_status.code), final_status.body)
	return true


# --- GTD-032 Assert Endpoints (SPEC §5.6) ---

func _main_assert_visible(args: Dictionary) -> Dictionary:
	return TestDriverAssertionHandler.assert_visible(get_tree().root, args)


func _main_assert_enabled(args: Dictionary) -> Dictionary:
	return TestDriverAssertionHandler.assert_enabled(get_tree().root, args)


func _main_assert_property(args: Dictionary) -> Dictionary:
	return TestDriverAssertionHandler.assert_property(get_tree().root, args)


# --- GTD-050 Screenshot Endpoints (SPEC §5.10) ---

func _main_screenshot_capture(args: Dictionary) -> Dictionary:
	return TestDriverScreenshotHandler.capture(get_tree(), args)


func _main_screenshot_region(args: Dictionary) -> Dictionary:
	return TestDriverScreenshotHandler.region(get_tree(), args)


# --- GTD-053 Window Endpoints (SPEC §5.10) ---

func _main_window_resize(args: Dictionary) -> Dictionary:
	return TestDriverWindowHandler.resize(get_tree(), args)


func _main_window_state(_args: Dictionary) -> Dictionary:
	return TestDriverWindowHandler.state(get_tree())



