class_name TestDriverInputHandler
extends RefCounted
## GTD-015/020 — input endpoints (SPEC §5.1/§5.3).
##
## Static main-thread helpers called from TestDriverApi._main_* handlers.
## All methods return the funnel contract shape {"code": int, "body": Dictionary}.
## Device constants per SPEC §6 (4.7+): keyboard 16, mouse 32, emulation -1.
##
## Click routing (GTD-020, graduated from Spike B / GTD-005 — engine-source
## verified against viewport.cpp / base_button.cpp):
##   - Targeted events resolve the node's owning Viewport and use
##     Viewport.push_input() — the ONLY path that works under --headless
##     (godot#73557: Input.parse_input_event is a no-op there).
##   - Coordinate invariant: Control.get_global_rect() returns the rect in the
##     CANVAS SPACE OF THE OWNING VIEWPORT — for a Control inside a SubViewport
##     that is SubViewport space, NOT window space. The rect center is already
##     the correct viewport-local position for push_input(local=true). The
##     affine_inverse mapping applies only when starting from WINDOW coords.
##   - godot#89757 caveat: mouse motion is ignored until the viewport has
##     received NOTIFICATION_VP_MOUSE_ENTER — hover must be established first.
##   - BaseButton::on_action_event requires status.hovering for mouse presses;
##     hovering is set ONLY by NOTIFICATION_MOUSE_ENTER from the viewport's
##     hover walk (_update_mouse_over).
##   - 200 means *injected*, not *processed*; the caller waits ≥1 frame
##     before asserting effects (SPEC §6 timing contract; auto-wait is
##     client-side, GTD-026).


## Full InputMap listing: one entry per action, events summarized per type.
## Always 200 (an empty InputMap is a valid, empty listing).
static func input_map() -> Dictionary:
	var actions: Array = []
	for action_name in InputMap.get_actions():
		var events: Array = []
		for ev in InputMap.action_get_events(action_name):
			events.append(_summarize_event(ev))
		actions.append({"name": String(action_name), "events": events})
	return {"code": 200, "body": {"ok": true, "data": {"actions": actions}}}


## Per-type event summary (SPEC §5.1): key → keycode/physical_keycode/device;
## mouse_button → button_index/device; joypad_button → button_index/device;
## joypad_motion → axis/axis_value/device; other types → {type} only.
static func _summarize_event(ev: InputEvent) -> Dictionary:
	var out := {"type": _event_type(ev)}
	var key := ev as InputEventKey
	if key != null:
		out["keycode"] = key.keycode
		out["physical_keycode"] = key.physical_keycode
		out["device"] = key.device
		return out
	var mouse := ev as InputEventMouseButton
	if mouse != null:
		out["button_index"] = mouse.button_index
		out["device"] = mouse.device
		return out
	var joy_button := ev as InputEventJoypadButton
	if joy_button != null:
		out["button_index"] = joy_button.button_index
		out["device"] = joy_button.device
		return out
	var joy_motion := ev as InputEventJoypadMotion
	if joy_motion != null:
		out["axis"] = joy_motion.axis
		out["axis_value"] = joy_motion.axis_value
		out["device"] = joy_motion.device
		return out
	return out


## Snake-cased InputEvent subclass name (key, mouse_button, joypad_motion...).
static func _event_type(ev: InputEvent) -> String:
	var cls := ev.get_class()
	# Strip the "InputEvent" prefix, snake-case the rest.
	var short := cls.substr("InputEvent".length())
	var out := ""
	for i in range(short.length()):
		var c := short[i]
		if c == c.to_upper() and i > 0 and short[i - 1] != short[i - 1].to_upper():
			out += "_"
		out += c.to_lower()
	return out


# --- POST /input/click (GTD-020, SPEC §5.3/§6) ---

## Target resolution for input endpoints: exactly one of "path" or "test_id".
## Returns {ok: true, node: Node, path: String} or {ok: false, code: int,
## error: Dictionary} (400 MISSING_PARAM / 404 NODE_NOT_FOUND /
## 404 TEST_ID_NOT_FOUND / 409 AMBIGUOUS_TEST_ID).
static func resolve_target(root: Node, args: Dictionary) -> Dictionary:
	var path: String = str(args.get("path", ""))
	var test_id: String = str(args.get("test_id", ""))
	if path.is_empty() == test_id.is_empty():
		return {
			"ok": false, "code": 400,
			"error": {"code": "MISSING_PARAM", "message": "exactly one of 'path' or 'test_id' is required"},
		}
	if not test_id.is_empty():
		# Whole-tree scan (GTD-014 machinery, reused raw — no envelope).
		var matches: Array[String] = []
		TestDriverNodeHandler._scan_test_id(root, test_id, matches)
		if matches.is_empty():
			return {
				"ok": false, "code": 404,
				"error": {"code": "TEST_ID_NOT_FOUND", "message": "no node carries test_id '%s'" % test_id},
			}
		if matches.size() > 1:
			return {
				"ok": false, "code": 409,
				"error": {"code": "AMBIGUOUS_TEST_ID", "message": "test_id '%s' matches %d nodes" % [test_id, matches.size()], "details": {"matches": matches}},
			}
		return {"ok": true, "node": root.get_node(NodePath(matches[0])), "path": matches[0]}
	var r := TestDriverNodeHandler.resolve(root, path)
	if not r.ok:
		return r
	return {"ok": true, "node": r.node, "path": String((r.node as Node).get_path())}


## POST /input/click — inject hover motion + press + release at the target
## node's center. Supports Control (GUI path) and CollisionObject2D (physics
## picking path). Returns the funnel shape.
static func click(tree: SceneTree, args: Dictionary) -> Dictionary:
	var root := tree.root
	var t := resolve_target(root, args)
	if not t.ok:
		return {"code": t.code, "body": {"ok": false, "error": t.error}}
	var node: Node = t.node
	if node is Control:
		# Capture viewport path BEFORE injection — button handlers run
		# synchronously during push_input and may trigger change_scene_to_file(),
		# freeing the node before we build the response (Bug #2).
		var vp := (node as Control).get_viewport()
		var vp_path := String(vp.get_path()) if vp else ""
		var err := _click_control(root, node as Control)
		if not err.is_empty():
			return {
				"code": 500,
				"body": {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": err}},
			}
		return {
			"code": 200,
			"body": {"ok": true, "data": {"injected": true, "target": t.path, "viewport": vp_path, "mode": "gui"}},
		}
	if node is CollisionObject2D:
		# Same pre-capture as the Control path (Bug #2).
		var vp := (node as CollisionObject2D).get_viewport()
		var vp_path := String(vp.get_path()) if vp else ""
		var err2 := _click_collision_object(root, node as CollisionObject2D)
		if not err2.is_empty():
			if err2.begins_with("PICKING_DISABLED:"):
				return {
					"code": 400,
					"body": {"ok": false, "error": {"code": "PICKING_DISABLED", "message": err2.substr("PICKING_DISABLED:".length())}},
				}
			return {
				"code": 500,
				"body": {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": err2}},
			}
		return {
			"code": 200,
			"body": {"ok": true, "data": {"injected": true, "target": t.path, "viewport": vp_path, "mode": "picking"}},
		}
	return {
		"code": 400,
		"body": {"ok": false, "error": {"code": "BAD_TARGET", "message": "node %s is not a Control or CollisionObject2D (type %s)" % [t.path, node.get_class()]}},
	}


## Core injection (spike-proven). Returns "" on success or an error message.
static func _click_control(root: Node, control: Control) -> String:
	# Target position: center of the control's rect — already viewport-local
	# (see class docblock coordinate invariant).
	var rect := control.get_global_rect()
	var local_pos := rect.get_center()

	var viewport := control.get_viewport()
	if viewport == null:
		return "no viewport for %s" % control.get_path()

	# Hover establishment (see class docblock): route the hover-establishing
	# MOTION through the root viewport at window-canvas coordinates for
	# container-attached SubViewports; press/release go directly to the
	# owning viewport (mouse-button delivery does not need mouse_in_viewport
	# — gui_find_control runs unconditionally).
	#
	# Window→sub coordinate chain (inverse of engine's forwarding):
	#   window_pos = container.get_global_transform_with_canvas()
	#                * (sub.get_final_transform() * (sub_pos * stretch_shrink))
	if viewport is SubViewport:
		var container := viewport.get_parent() as SubViewportContainer
		if container != null:
			var shrink := container.stretch_shrink if container.stretch else 1
			var window_pos: Vector2 = container.get_global_transform_with_canvas() \
					* (viewport.get_final_transform() * (local_pos * shrink))
			var root_local: Vector2 = root.get_final_transform().affine_inverse() * window_pos
			root.push_input(_make_mouse_motion(root_local, root_local), true)
		else:
			# Standalone SubViewport (no container): _update_mouse_over runs
			# locally once mouse-in-viewport state is set via the public API.
			viewport.notify_mouse_entered()
			viewport.push_input(_make_mouse_motion(local_pos, local_pos), true)
	else:
		# Root Window: mouse-in-viewport state is already established
		# (headless sets it at startup; windowed via real mouse enter).
		viewport.push_input(_make_mouse_motion(local_pos, local_pos), true)

	# Inject: press + release. in_local_coordinates=true — event positions
	# are in the viewport's own coordinate space (matches get_global_rect).
	viewport.push_input(_make_mouse_button(local_pos, local_pos, true), true)
	viewport.push_input(_make_mouse_button(local_pos, local_pos, false), true)
	return ""


## Physics-picking injection path (GTD-030). CollisionObject2D targets receive
## mouse input through Viewport physics picking, NOT the GUI path:
##   - push_input queues unconsumed mouse events into physics_picking_events
##     when physics_object_picking is on (viewport.cpp _push_unhandled_input_internal).
##   - _process_picking() consumes the queue on PHYSICS frames
##     (scene_tree.cpp _picking_viewports group) — callers must wait
##     >=1 physics_frame before asserting signals.
##   - _process_picking early-returns and CLEARS the queue when
##     !gui.mouse_in_viewport — the hover motion is mandatory here too.
##   - GUI has precedence: a Control under the click point consumes the event
##     before picking ever sees it (documented caveat, SPEC §6).
## Returns "" on success, "PICKING_DISABLED:<msg>" or a plain error message.
static func _click_collision_object(root: Node, co: CollisionObject2D) -> String:
	var viewport := co.get_viewport()
	if viewport == null:
		return "no viewport for %s" % co.get_path()
	if not viewport.physics_object_picking:
		return "PICKING_DISABLED:viewport %s has physics_object_picking disabled — enable it (root viewport: project setting physics/common/enable_object_picking; SubViewports default to false)" % String(viewport.get_path())

	var local_pos := _collision_click_point(co)
	if local_pos == Vector2.INF:
		return "no enabled CollisionShape2D under %s and node has no usable position" % co.get_path()

	# Hover establishment — same routing rules as the GUI path (see
	# _click_control): container-attached SubViewports get their mouse-in-
	# viewport state via the ROOT's hover walk at window coords; standalone
	# SubViewports and root Windows need notify_mouse_entered() to set
	# gui.mouse_in_viewport=true before _process_picking runs.
	#
	# _process_picking gate (viewport.cpp):
	#   if (!gui.mouse_in_viewport || gui.subwindow_over) {
	#       physics_picking_events.clear(); return; }   ← kills queue silently
	#
	# notify_mouse_entered() is idempotent: the engine guards double-calls
	# internally (WARN_PRINT_ED — editor-only, never printed in exported games
	# or headless CI). Always safe to call before the first push_input.
	if viewport is SubViewport:
		var container := viewport.get_parent() as SubViewportContainer
		if container != null:
			var shrink := container.stretch_shrink if container.stretch else 1
			var window_pos: Vector2 = container.get_global_transform_with_canvas() \
					* (viewport.get_final_transform() * (local_pos * shrink))
			var root_local: Vector2 = root.get_final_transform().affine_inverse() * window_pos
			root.push_input(_make_mouse_motion(root_local, root_local), true)
		else:
			viewport.notify_mouse_entered()
			viewport.push_input(_make_mouse_motion(local_pos, local_pos), true)
	else:
		# Root Window: notify_mouse_entered() sets mouse_in_viewport=true.
		# Without this, _process_picking immediately clears the picking queue.
		viewport.notify_mouse_entered()
		viewport.push_input(_make_mouse_motion(local_pos, local_pos), true)

	# Press + release: unconsumed by GUI (no Control at the point) → queued
	# into physics_picking_events by _push_unhandled_input_internal →
	# delivered by _process_picking on the next physics frame(s).
	#
	# NOTE: do NOT "fall back" to calling co._input_event() directly. That is
	# the VIRTUAL method (only exists when the game script overrides it —
	# calling it on a plain Area2D aborts with "Nonexistent function"), it
	# does NOT emit the input_event signal, and it bypasses the real input
	# pipeline (no mouse_entered, no physics_2d_mouseover tracking, hardcoded
	# shape_idx=0). Physics frames always tick under --headless; delivery is
	# guaranteed by notify_mouse_entered() above + the root-size fix.
	viewport.push_input(_make_mouse_button(local_pos, local_pos, true), true)
	viewport.push_input(_make_mouse_button(local_pos, local_pos, false), true)
	return ""


## Click point for a CollisionObject2D: first enabled CollisionShape2D child,
## shape-geometry aware; fallback to the node's global_position. Returns
## Vector2.INF when nothing usable exists.
static func _collision_click_point(co: CollisionObject2D) -> Vector2:
	for child in co.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var shape := shape_node.shape
		var origin := shape_node.global_position
		if shape is RectangleShape2D or shape is CircleShape2D or shape is CapsuleShape2D:
			return origin  # centered on the shape node origin
		if shape is ConvexPolygonShape2D:
			var points: PackedVector2Array = (shape as ConvexPolygonShape2D).points
			if not points.is_empty():
				var sum := Vector2.ZERO
				for p in points:
					sum += p
				return origin + sum / points.size()
			return origin
		if shape is SegmentShape2D:
			var seg := shape as SegmentShape2D
			return origin + (seg.a + seg.b) * 0.5
		return origin
	return co.global_position


static func _make_mouse_button(local_pos: Vector2, global_pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.device = TestDriverCompat.device_id_mouse()
	ev.pressed = pressed
	ev.position = local_pos
	ev.global_position = global_pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


static func _make_mouse_motion(local_pos: Vector2, global_pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = local_pos
	ev.global_position = global_pos
	# relative must be zero on the synthetic enter-motion so hover logic
	# doesn't see a phantom jump.
	ev.relative = Vector2.ZERO
	return ev


# --- POST /input/type (GTD-021, SPEC §5.3/§6) ---

## Type text into a target Control (LineEdit/TextEdit): grab focus, then one
## pressed+released InputEventKey pair per character (unicode set) via the
## owning viewport push_input(local=true). Targeted path — works headless;
## typing NEVER goes through Input.parse_input_event (needs a focused Control).
static func type_text(tree: SceneTree, args: Dictionary) -> Dictionary:
	var root := tree.root
	var t := resolve_target(root, args)
	if not t.ok:
		return {"code": t.code, "body": {"ok": false, "error": t.error}}
	var text: String = str(args.get("text", ""))
	if text.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "'text' is required and must be non-empty"}},
		}
	var node: Node = t.node
	if not node is Control:
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "BAD_TARGET", "message": "node %s is not a Control (type %s)" % [t.path, node.get_class()]}},
		}
	var control := node as Control
	control.grab_focus()
	var viewport := control.get_viewport()
	if viewport == null:
		return {
			"code": 500,
			"body": {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "no viewport for %s" % t.path}},
		}
	for c in text:
		var ev := InputEventKey.new()
		ev.unicode = c.unicode_at(0)
		ev.pressed = true
		viewport.push_input(ev, true)
		var up := ev.duplicate() as InputEventKey
		up.pressed = false
		viewport.push_input(up, true)
	return {
		"code": 200,
		"body": {"ok": true, "data": {"injected": true, "chars": text.length(), "target": t.path}},
	}


# --- POST /input/key (GTD-021, SPEC §5.3/§6) ---

## Inject a key press+release. Resolution order for the "key" param:
##   1. InputMap action name (e.g. "ui_accept") → first InputEventKey of the
##      action's event list (keycode/physical_keycode taken from it).
##   2. KEY_* constant name (e.g. "KEY_ENTER") via the @GlobalScope constant map.
## Global form (no target): Input.parse_input_event + Input.flush_buffered_events()
## — the godot#73557 headless workaround (flush delivers events AND updates
## action state). Targeted form (path/test_id): grab_focus + owning-viewport
## push_input, works headless.
static func key(tree: SceneTree, args: Dictionary) -> Dictionary:
	var root := tree.root
	var key_name := str(args.get("key", ""))
	if key_name.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "'key' is required (action name or KEY_* constant)"}},
		}
	var resolved := _resolve_key(key_name)
	if resolved.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "UNKNOWN_KEY", "message": "'%s' is neither an InputMap action nor a KEY_* constant" % key_name}},
		}
	# Optional target: route through the owning viewport instead of the global path.
	var target_path := ""
	if args.has("path") or args.has("test_id"):
		var t := resolve_target(root, args)
		if not t.ok:
			return {"code": t.code, "body": {"ok": false, "error": t.error}}
		var node: Node = t.node
		if not node is Control:
			return {
				"code": 400,
				"body": {"ok": false, "error": {"code": "BAD_TARGET", "message": "node %s is not a Control (type %s)" % [t.path, node.get_class()]}},
			}
		target_path = t.path
		var control := node as Control
		control.grab_focus()
		var viewport := control.get_viewport()
		if viewport == null:
			return {
				"code": 500,
				"body": {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "no viewport for %s" % t.path}},
			}
		viewport.push_input(_make_key(resolved, true), true)
		viewport.push_input(_make_key(resolved, false), true)
	else:
		# Global path: parse + flush (headless workaround, godot#73557).
		Input.parse_input_event(_make_key(resolved, true))
		Input.parse_input_event(_make_key(resolved, false))
		Input.flush_buffered_events()
	return {
		"code": 200,
		"body": {"ok": true, "data": {"injected": true, "key": key_name, "device": resolved["device"], "target": target_path}},
	}


## POST /input/key_down (GTD-054) — inject ONLY the pressed event so held
## state (Input.is_action_pressed) is observable across frames. Same key
## resolution and routing as /input/key.
static func key_down(tree: SceneTree, args: Dictionary) -> Dictionary:
	return _key_phase(tree, args, true)


## POST /input/key_up (GTD-054) — inject ONLY the released event.
static func key_up(tree: SceneTree, args: Dictionary) -> Dictionary:
	return _key_phase(tree, args, false)


static func _key_phase(tree: SceneTree, args: Dictionary, pressed: bool) -> Dictionary:
	var root := tree.root
	var key_name := str(args.get("key", ""))
	if key_name.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "'key' is required (action name or KEY_* constant)"}},
		}
	var resolved := _resolve_key(key_name)
	if resolved.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "UNKNOWN_KEY", "message": "'%s' is neither an InputMap action nor a KEY_* constant" % key_name}},
		}
	var target_path := ""
	if args.has("path") or args.has("test_id"):
		var t := resolve_target(root, args)
		if not t.ok:
			return {"code": t.code, "body": {"ok": false, "error": t.error}}
		var node: Node = t.node
		if not node is Control:
			return {
				"code": 400,
				"body": {"ok": false, "error": {"code": "BAD_TARGET", "message": "node %s is not a Control (type %s)" % [t.path, node.get_class()]}},
			}
		target_path = t.path
		var control := node as Control
		control.grab_focus()
		var viewport := control.get_viewport()
		if viewport == null:
			return {
				"code": 500,
				"body": {"ok": false, "error": {"code": "INTERNAL_ERROR", "message": "no viewport for %s" % t.path}},
			}
		viewport.push_input(_make_key(resolved, pressed), true)
	else:
		# Global path: parse + flush (headless workaround, godot#73557) so
		# Input.is_action_pressed updates immediately.
		Input.parse_input_event(_make_key(resolved, pressed))
		Input.flush_buffered_events()
	return {
		"code": 200,
		"body": {"ok": true, "data": {"injected": true, "key": key_name, "device": resolved["device"], "target": target_path, "pressed": pressed}},
	}


## Resolution result: {keycode, physical_keycode, unicode, device} or {} when
## unresolvable. Device per SPEC §6 (4.7+ keyboard = 16; GTD-022 adds the
## compat shim for 4.3–4.6).
static func _resolve_key(key_name: String) -> Dictionary:
	# 1. InputMap action → first key event.
	if InputMap.has_action(key_name):
		for ev in InputMap.action_get_events(key_name):
			var k := ev as InputEventKey
			if k != null:
				return {"keycode": k.keycode, "physical_keycode": k.physical_keycode, "unicode": 0, "device": TestDriverCompat.device_id_keyboard()}
	# 2. KEY_* constant via the generated name→keycode map (ClassDB does NOT
	#    expose @GlobalScope constants; Expression can't resolve them either —
	#    the map references the GDScript globals directly, parse-time checked).
	if key_name.begins_with("KEY_") and TestDriverKeyMap.MAP.has(key_name):
		return {"keycode": TestDriverKeyMap.MAP[key_name] as Key, "physical_keycode": KEY_NONE, "unicode": 0, "device": TestDriverCompat.device_id_keyboard()}
	return {}


static func _make_key(resolved: Dictionary, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = resolved["keycode"]
	ev.physical_keycode = resolved["physical_keycode"]
	ev.unicode = resolved["unicode"]
	ev.device = resolved["device"]
	ev.pressed = pressed
	return ev
