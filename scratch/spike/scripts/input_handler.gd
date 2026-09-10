extends Node
class_name SpikeInputHandler
## GTD-005 (Spike B) — minimal click injection proving the SPEC §6 routing.
##
## Routing contract (SPEC §6):
##   - Targeted events resolve the node's owning Viewport and use
##     Viewport.push_input() — the ONLY path that works under --headless
##     (godot#73557: Input.parse_input_event is a no-op there).
##   - Coordinate invariant: global → viewport-local via
##     viewport.get_final_transform().affine_inverse() * global_pos
##     (handles stretch modes, SubViewportContainer scaling, camera offsets).
##   - godot#89757 caveat: mouse motion is ignored until the viewport has
##     received NOTIFICATION_VP_MOUSE_ENTER — send it before the first motion.
##   - 200 means *injected*, not *processed*; the caller waits ≥1 frame
##     before asserting effects (SPEC §6 timing contract).


## Click the center of the Control at `node_path` (absolute, e.g. /root/Main/Button).
## Returns "" on success or an error message. MUST run on the main thread
## (marshal through Dispatcher from HTTP worker threads).
func click_at(node_path: String) -> String:
	var node := get_tree().root.get_node_or_null(NodePath(node_path))
	if node == null:
		return "no node at %s" % node_path
	if not node is Control:
		return "node at %s is not a Control" % node_path
	var control := node as Control

	# Target position: center of the control's rect. Control.get_global_rect()
	# returns the rect in the CANVAS SPACE OF THE OWNING VIEWPORT — for a
	# Control inside a SubViewport that is SubViewport space (e.g. 200x200),
	# NOT window space. So the rect center is already the correct
	# viewport-local position for push_input(in_local_coordinates=true).
	# (Refines SPEC §6: the affine_inverse mapping applies when starting from
	# WINDOW coordinates; starting from the Control's own rect, the coords
	# are already viewport-local.)
	var rect := control.get_global_rect()
	var local_pos := rect.get_center()

	# Owning viewport: the SubViewport for controls inside a
	# SubViewportContainer, otherwise the root viewport.
	var viewport := control.get_viewport()
	if viewport == null:
		return "no viewport for %s" % node_path

	# Hover establishment (engine-source finding, viewport.cpp 4.4):
	# - push_input never sets gui.mouse_in_viewport, and _update_mouse_over()
	#   EARLY-RETURNS for SubViewports attached to a SubViewportContainer
	#   (is_attached_in_viewport guard) — so a motion pushed directly into
	#   such a SubViewport can never resolve hover, and without
	#   NOTIFICATION_MOUSE_ENTER BaseButton::on_action_event ignores mouse
	#   presses (status.hovering required, base_button.cpp).
	# - The ONLY path that sets hover in a container-attached SubViewport is
	#   the ROOT viewport's _update_mouse_over recursion: it finds the
	#   SubViewportContainer, sends NOTIFICATION_VP_MOUSE_ENTER to the sub,
	#   and resolves hover inside it (with the container/stretch transform).
	# Therefore: route the hover-establishing MOTION through the root
	# viewport at window-canvas coordinates, then push press/release
	# directly into the owning viewport (mouse-button delivery does not
	# need mouse_in_viewport — gui_find_control runs unconditionally).
	#
	# Window→sub coordinate chain (inverse of engine's forwarding):
	#   window_pos = container.get_global_transform_with_canvas()
	#                * (sub.get_final_transform() * (sub_pos * stretch_shrink))
	var root := get_tree().root
	if viewport is SubViewport:
		var container := viewport.get_parent() as SubViewportContainer
		if container != null:
			var shrink := container.stretch_shrink if container.stretch else 1
			var window_pos: Vector2 = container.get_global_transform_with_canvas() \
					* (viewport.get_final_transform() * (local_pos * shrink))
			var root_local: Vector2 = root.get_final_transform().affine_inverse() * window_pos
			root.push_input(_make_mouse_motion(root_local, root_local, true), true)
		else:
			# Standalone SubViewport (no container): _update_mouse_over runs
			# locally once mouse-in-viewport state is set via the public API.
			viewport.notify_mouse_entered()
			viewport.push_input(_make_mouse_motion(local_pos, local_pos, true), true)
	else:
		# Root Window: mouse-in-viewport state is already established
		# (headless sets it at startup; windowed via real mouse enter).
		viewport.push_input(_make_mouse_motion(local_pos, local_pos, true), true)

	# Inject: press + release. in_local_coordinates=true — event positions
	# are in the viewport's own coordinate space (matches get_global_rect).
	var press := _make_mouse_button(local_pos, local_pos, true)
	var release := _make_mouse_button(local_pos, local_pos, false)
	viewport.push_input(press, true)
	viewport.push_input(release, true)
	return ""


func _make_mouse_button(local_pos: Vector2, global_pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = local_pos
	ev.global_position = global_pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


func _make_mouse_motion(local_pos: Vector2, global_pos: Vector2, first: bool) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = local_pos
	ev.global_position = global_pos
	if first:
		# relative must be zero on the synthetic enter-motion so hover logic
		# doesn't see a phantom jump.
		ev.relative = Vector2.ZERO
	return ev
