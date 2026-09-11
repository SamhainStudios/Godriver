class_name TestDriverSignalHandler
extends Object
## GTD-031 — Signal observation and waiting handler (SPEC §5.5).
##
## Tracks watched signals, buffers emissions, and supports non-blocking poll
## and worker-thread long-poll waiting.
## Signal connections/disconnections execute exclusively on the main thread (godot#117396).

const UNSET := &"__GTD_UNSET__"

## Helper class instantiated per watched (node, signal) pair.
## Holds member variables for target_path and signal_name so signal args
## pass directly into on_signal without argument count ambiguity.
class SignalWatcher extends Object:
	var target_path: String
	var signal_name: String
	var node: Node

	func _init(p_node: Node, p_path: String, p_signal: String) -> void:
		node = p_node
		target_path = p_path
		signal_name = p_signal

	func on_signal(
		a0: Variant = UNSET, a1: Variant = UNSET, a2: Variant = UNSET, a3: Variant = UNSET,
		a4: Variant = UNSET, a5: Variant = UNSET, a6: Variant = UNSET, a7: Variant = UNSET
	) -> void:
		var signal_args: Array = []
		for arg in [a0, a1, a2, a3, a4, a5, a6, a7]:
			if arg is StringName and StringName(arg) == UNSET:
				break
			signal_args.append(TestDriverSerializer.encode(arg))
		TestDriverSignalHandler.record_emission(target_path, signal_name, signal_args)


# --- Shared State (Thread-Safe) ---

static var _watchers: Dictionary = {} # "path:signal" -> SignalWatcher
static var _emissions: Array = [] # Array of Dictionary
static var _seq: int = 0
static var _reset_flag: bool = false
static var _mutex: Mutex = Mutex.new()


## Record an emission into the thread-safe buffer.
static func record_emission(target_path: String, signal_name: String, args: Array) -> void:
	_mutex.lock()
	_seq += 1
	_emissions.append({
		"target": target_path,
		"signal": signal_name,
		"args": args,
		"timestamp": Time.get_unix_time_from_system(),
		"frame": Engine.get_process_frames(),
		"seq": _seq
	})
	_mutex.unlock()


## Main-thread method to register a signal watcher.
static func watch(tree: SceneTree, args: Dictionary) -> Dictionary:
	var root := tree.root
	var resolved := TestDriverInputHandler.resolve_target(root, args)
	if not resolved.get("ok", false):
		return {
			"code": resolved.get("code", 400),
			"body": {"ok": false, "error": resolved.get("error", {})}
		}
	var node: Node = resolved.get("node")
	var signal_name: String = str(args.get("signal", ""))

	if signal_name.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "missing required parameter 'signal'"}}
		}

	if not node.has_signal(signal_name):
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "SIGNAL_NOT_FOUND", "message": "node '%s' has no signal '%s'" % [node.get_path(), signal_name]}}
		}

	var node_path := String(node.get_path())
	var key := "%s:%s" % [node_path, signal_name]

	_mutex.lock()
	_reset_flag = false
	var already_watching := _watchers.has(key)
	_mutex.unlock()

	if not already_watching:
		var watcher := SignalWatcher.new(node, node_path, signal_name)
		var err := node.connect(signal_name, Callable(watcher, "on_signal"))
		if err != OK:
			return {
				"code": 500,
				"body": {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "failed to connect signal '%s' on '%s': error %d" % [signal_name, node_path, err]}}
			}
		_mutex.lock()
		_watchers[key] = watcher
		_mutex.unlock()

	return {
		"code": 200,
		"body": {"ok": true, "data": {"watched": true, "target": node_path, "signal": signal_name}}
	}


## Main-thread / Worker method to poll emissions.
static func poll(args: Dictionary) -> Dictionary:
	var filter_target := str(args.get("target", ""))
	var filter_signal := str(args.get("signal", ""))

	_mutex.lock()
	var matched: Array = []
	var remaining: Array = []

	for em in _emissions:
		var match_target: bool = filter_target.is_empty() or String(em["target"]) == filter_target
		var match_signal: bool = filter_signal.is_empty() or String(em["signal"]) == filter_signal
		if match_target and match_signal:
			matched.append(em)
		else:
			remaining.append(em)

	_emissions = remaining
	_mutex.unlock()

	return {
		"code": 200,
		"body": {"ok": true, "data": {"emissions": matched}}
	}


## Worker-thread helper for long-polling /signal/wait.
## Checks if a matching emission occurred after min_seq or if reset occurred.
static func check_wait_status(target_path: String, signal_name: String, min_seq: int) -> Dictionary:
	_mutex.lock()
	if _reset_flag:
		_mutex.unlock()
		return {"status": "reset"}

	for em in _emissions:
		if int(em["seq"]) > min_seq:
			var match_target: bool = target_path.is_empty() or String(em["target"]) == target_path
			var match_signal: bool = signal_name.is_empty() or String(em["signal"]) == signal_name
			if match_target and match_signal:
				var res := {"status": "found", "emission": em, "seq": int(em["seq"])}
				_mutex.unlock()
				return res

	var current_seq := _seq
	_mutex.unlock()
	return {"status": "waiting", "seq": current_seq}


## Get current sequence number.
static func get_current_seq() -> int:
	_mutex.lock()
	var s := _seq
	_mutex.unlock()
	return s


## Clear all watchers and emissions on main thread (called by /reset).
static func clear_all() -> void:
	_mutex.lock()
	_reset_flag = true
	var watchers_copy := _watchers.duplicate()
	_watchers.clear()
	_emissions.clear()
	_mutex.unlock()

	for watcher in watchers_copy.values():
		var w := watcher as SignalWatcher
		if w != null and is_instance_valid(w.node) and w.node.is_connected(w.signal_name, Callable(w, "on_signal")):
			w.node.disconnect(w.signal_name, Callable(w, "on_signal"))

