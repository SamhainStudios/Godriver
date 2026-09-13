class_name TestDriverSceneHandler
extends RefCounted
## GTD-015 — GET /scene/current (SPEC §5.1).
##
## Static main-thread helpers called from TestDriverApi._main_* handlers.
## All methods return the funnel contract shape {"code": int, "body": Dictionary}.


## Current scene identity: resource path + absolute node path.
## 500 INTERNAL_ERROR when the tree has no current scene (e.g. before the
## main scene is instanced).
static func current(tree: SceneTree) -> Dictionary:
	var scene := tree.current_scene
	if scene == null:
		return {
			"code": 500,
			"body": {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "no current scene (main scene not yet loaded)"}},
		}
	return {
		"code": 200,
		"body": {"ok": true, "data": {
			"scene": scene.scene_file_path,
			"node": String(scene.get_path()),
		}},
	}


const RESET_READINESS_MS := 5000
## Meta key marking nodes the orphan sweep must keep (escape hatch for test
## harnesses that live directly under /root, e.g. GdUnit runner nodes).
const KEEP_META := "godriver_keep"


## POST /reset — full §5.0 isolation sequence (GTD-016).
##
## ASYNC: runs as a coroutine on the main thread (awaits process_frame), so it
## must NOT be called through the synchronous dispatcher funnel — the caller
## (api_handler._dispatch_reset) starts it via a sync start-task and polls a
## shared slot. Completion is delivered by calling `done(result)` where result
## is the funnel shape {"code": int, "body": Dictionary}.
##
## Steps 1–2 (signal watchers) land with GTD-030 (Phase 3) — no watchers exist yet.
static func reset(tree: SceneTree, tween_mode: String, done: Callable) -> void:
	var result := {
		"code": 200,
		"body": {"ok": true, "data": {"reloaded_scene": "", "scene_ready": true}},
	}
	# Steps 1–2: disconnect signal watchers & unblock pending waits (GTD-031).
	TestDriverSignalHandler.clear_all()
	# Step 3: determinism state.
	Engine.time_scale = 1.0
	tree.paused = false
	# Step 4: state autoload reset (fresh script instance → copy script vars).
	var state_missing := _reset_state_autoload(tree)
	# Step 4b (Bug #3): reset additional autoloads from the configured list.
	# Game devs configure which autoloads carry test-relevant state (e.g.
	# TimeState, InventoryManager) via godriver/reset_autoloads. Autoloads
	# NOT in this list (AudioManager, SettingsManager) are left untouched.
	var extra_autoloads: PackedStringArray = ProjectSettings.get_setting(
		"godriver/reset_autoloads", PackedStringArray())
	var extra_missing: Array[String] = []
	for autoload_name in extra_autoloads:
		if _reset_named_autoload(tree, autoload_name):
			extra_missing.append(autoload_name)
	# Step 5: load the MAIN scene — NOT reload_current_scene(), which would
	# reload whatever scene is current after /scene/load (§5.0).
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene.is_empty():
		done.call(_internal("no application/run/main_scene configured"))
		return
	var old_scene := tree.current_scene
	var err := tree.change_scene_to_file(main_scene)
	if err != OK:
		done.call(_internal("change_scene_to_file failed (error %d)" % err))
		return
	# Atomicity contract (§5.0): 200 only after the new scene is live and
	# ready. Await process_frame until current_scene changes, then poll
	# is_node_ready() (never `await ready` — it may already have fired).
	var deadline := Time.get_ticks_msec() + RESET_READINESS_MS
	while tree.current_scene == null or tree.current_scene == old_scene:
		if Time.get_ticks_msec() > deadline:
			done.call(_scene_timeout("new scene did not appear within %dms" % RESET_READINESS_MS))
			return
		await tree.process_frame
	while not tree.current_scene.is_node_ready():
		if Time.get_ticks_msec() > deadline:
			done.call(_scene_timeout("new scene not ready within %dms (async _ready?)" % RESET_READINESS_MS))
			return
		await tree.process_frame
	# Step 6: tweens per tween_mode. Tweens created via SceneTree.create_tween()
	# are tree-bound and survive change_scene_to_file — they must not leak
	# callbacks into the new scenario.
	if tween_mode == "await":
		var tween_deadline := Time.get_ticks_msec() + RESET_READINESS_MS
		while tree.get_processed_tweens().size() > 0:
			if Time.get_ticks_msec() > tween_deadline:
				break
			await tree.process_frame
	for tween in tree.get_processed_tweens():
		tween.kill()
	# Step 7: orphan sweep — queue_free() only (deferred teardown; never free(),
	# which could destroy nodes while pending callables are still queued).
	_sweep_orphans(tree)
	# Step 8: discard injected-but-unprocessed input from the old scenario.
	Input.flush_buffered_events()
	if state_missing:
		# SPEC §5.0: reset proceeds without the state step, but the response
		# is 409 STATE_AUTOLOAD_MISSING so tests notice the misconfiguration.
		done.call({
			"code": 409,
			"body": {"ok": false, "error": {"code": "STATE_AUTOLOAD_MISSING", "message": "reset completed, but state autoload is missing (reset proceeded without the state step)"}},
		})
		return
	if not extra_missing.is_empty():
		result.body.data["missing_autoloads"] = extra_missing
	result.body.data.reloaded_scene = main_scene
	done.call(result)
	# GTD-024: record the transition in the driver-tracked asset inventory.
	TestDriverAssetsHandler.track(main_scene, "reset")


## Reset the state autoload to its script-declared initial values by copying
## from a fresh script instance. Autoloads persist across scene changes, so a
## scene reload alone does NOT reset them (§5.0 step 4).
## Returns true when the autoload is missing (→ 409, reset still proceeds).
static func _reset_state_autoload(tree: SceneTree) -> bool:
	var autoload_name: String = ProjectSettings.get_setting("godriver/state_autoload", "GameState")
	return _reset_named_autoload(tree, autoload_name)


## Reset a specific named autoload singleton to its initial values.
## Returns true if the autoload node or its script is missing.
static func _reset_named_autoload(tree: SceneTree, autoload_name: String) -> bool:
	var node := tree.root.get_node_or_null(NodePath("/root/" + autoload_name))
	if node == null or node.get_script() == null:
		return true
	var script: Script = node.get_script()
	var fresh: Object = script.new()
	for p in fresh.get_property_list():
		var usage: int = p.get("usage", 0)
		# SCRIPT_VARIABLE only — plain (non-exported) script vars carry that
		# flag but NOT STORAGE; requiring STORAGE would skip them entirely
		# (same filter as TestDriverStateHandler.read_state).
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var prop: String = p.get("name", "")
			node.set(prop, fresh.get(prop))
	fresh.free()
	return false


## Orphan sweep (§5.0 step 7): every direct child of /root NOT on the
## allowlist is queue_free()d. Allowlist: the current scene instance, all
## ProjectSettings autoload/* nodes, nodes carrying the `godriver_keep`
## meta (escape hatch for test harnesses), and engine auto-named nodes
## ("@..." — internal/GdUnit-style infrastructure, never test orphans).
static func _sweep_orphans(tree: SceneTree) -> void:
	var root := tree.root
	var keep := {}
	if tree.current_scene != null:
		keep[tree.current_scene.get_instance_id()] = true
	for child in root.get_children():
		if ProjectSettings.has_setting("autoload/" + String(child.name)):
			keep[child.get_instance_id()] = true
		elif child.has_meta(KEEP_META):
			keep[child.get_instance_id()] = true
		elif String(child.name).begins_with("@"):
			# Engine auto-generated name → internal node (debug helpers,
			# test-runner hosts). Never a test-created orphan.
			keep[child.get_instance_id()] = true
	for child in root.get_children():
		if not keep.has(child.get_instance_id()):
			child.queue_free()


static func _internal(message: String) -> Dictionary:
	return {
		"code": 500,
		"body": {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": message}},
	}


static func _scene_timeout(message: String) -> Dictionary:
	return {
		"code": 504,
		"body": {"ok": false, "error": {"code": "SCENE_READY_TIMEOUT", "message": message}},
	}


# --- POST /scene/load (GTD-023, SPEC §5.0) ---

## POST /scene/load — change to an arbitrary scene with /reset's readiness
## semantics (§5.0): 200 only after the new scene is live and ready.
##
## ASYNC: same coroutine contract as reset() — started via a sync start-task,
## completion delivered through `done(result)` (funnel shape).
##
## Difference from /reset: load is a TRANSITION, not a cleanup — the tween
## kill and orphan-sweep steps are SKIPPED (those belong to the isolation
## contract of /reset; a test that needs them calls /reset).
static func load_scene(tree: SceneTree, path: String, done: Callable, tween_mode: String = "none") -> void:
	if path.is_empty():
		done.call({
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "'path' is required (res:// path to a .tscn)"}},
		})
		return
	if not ResourceLoader.exists(path, "PackedScene"):
		done.call({
			"code": 404,
			"body": {"ok": false, "error": {"code": "SCENE_NOT_FOUND", "message": "no loadable PackedScene at '%s'" % path}},
		})
		return
	var old_scene := tree.current_scene
	var err := tree.change_scene_to_file(path)
	if err != OK:
		done.call(_internal("change_scene_to_file failed (error %d)" % err))
		return
	# Readiness contract (§5.0, shared with reset): await process_frame until
	# current_scene changes, then poll is_node_ready() (never `await ready`).
	var deadline := Time.get_ticks_msec() + RESET_READINESS_MS
	while tree.current_scene == null or tree.current_scene == old_scene:
		if Time.get_ticks_msec() > deadline:
			done.call(_scene_timeout("new scene did not appear within %dms" % RESET_READINESS_MS))
			return
		await tree.process_frame
	while not tree.current_scene.is_node_ready():
		if Time.get_ticks_msec() > deadline:
			done.call(_scene_timeout("new scene not ready within %dms (async _ready?)" % RESET_READINESS_MS))
			return
		await tree.process_frame
	# Optional tween handling (Issue #4):
	if tween_mode == "await":
		var tween_deadline := Time.get_ticks_msec() + RESET_READINESS_MS
		while tree.get_processed_tweens().size() > 0:
			if Time.get_ticks_msec() > tween_deadline:
				break
			await tree.process_frame
	if tween_mode == "kill" or tween_mode == "await":
		for tween in tree.get_processed_tweens():
			tween.kill()
	done.call({
		"code": 200,
		"body": {"ok": true, "data": {"loaded": path, "scene_ready": true}},
	})
	# GTD-024: record the transition in the driver-tracked asset inventory.
	TestDriverAssetsHandler.track(path, "scene_load")


## POST /wait/tween — wait for all active SceneTree tweens to complete (Issue #8).
## ASYNC: coroutine awaiting process_frame.
static func wait_tweens(tree: SceneTree, timeout_ms: int, done: Callable) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while tree.get_processed_tweens().size() > 0:
		if Time.get_ticks_msec() > deadline:
			done.call({
				"code": 504,
				"body": {
					"ok": false,
					"error": {
						"code": "TWEEN_TIMEOUT",
						"message": "tweens did not complete within %dms" % timeout_ms
					}
				}
			})
			return
		await tree.process_frame
	done.call({
		"code": 200,
		"body": {
			"ok": true,
			"data": {
				"tweens_remaining": 0
			}
		}
	})
