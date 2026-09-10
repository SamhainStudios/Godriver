class_name TestDriverUiHandler
extends RefCounted
## GTD-025 — GET /ui/layout/<path> (SPEC §5.1).
##
## Control layout inspection: bounds via get_global_rect() (viewport-canvas
## coords — GTD-005 invariant; on 4.7+ get_global_rect already accounts for
## Control.offset_transform_*), visibility, anchors, and optional recursive
## children layouts (?depth=N).
##
## Static main-thread helpers; funnel contract shape {"code", "body"}.

const MAX_DEPTH := 16


## Layout snapshot for one Control. children included only when depth > 0.
static func layout(root: Node, control: Control, path: String, depth: int) -> Dictionary:
	var rect := control.get_global_rect()
	var out := {
		"path": path,
		"type": control.get_class(),
		"visible": control.visible,
		"visible_in_tree": control.is_visible_in_tree(),
		"global_rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
		"position": {"x": control.position.x, "y": control.position.y},
		"size": {"x": control.size.x, "y": control.size.y},
		"anchors": {
			"left": control.anchor_left, "top": control.anchor_top,
			"right": control.anchor_right, "bottom": control.anchor_bottom,
			"offset_left": control.offset_left, "offset_top": control.offset_top,
			"offset_right": control.offset_right, "offset_bottom": control.offset_bottom,
		},
		"pivot": {"x": control.pivot_offset.x, "y": control.pivot_offset.y},
		"rotation": control.rotation,
		"scale": {"x": control.scale.x, "y": control.scale.y},
		"mouse_filter": control.mouse_filter,
	}
	if depth > 0:
		var children: Array = []
		for child in control.get_children():
			var c := child as Control
			if c == null:
				continue
			# layout() returns the data Dictionary directly (not the funnel shape).
			children.append(layout(root, c, String(c.get_path()), depth - 1))
		out["children"] = children
	return out


## GET /ui/layout/<path> or /ui/layout?test_id= — funnel shape.
static func get_layout(tree: SceneTree, args: Dictionary) -> Dictionary:
	var root := tree.root
	var t := TestDriverInputHandler.resolve_target(root, args)
	if not t.ok:
		return {"code": t.code, "body": {"ok": false, "error": t.error}}
	var node: Node = t.node
	if not node is Control:
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "BAD_TARGET", "message": "node %s is not a Control (type %s)" % [t.path, node.get_class()]}},
		}
	var depth := int(args.get("depth", 0))
	if depth < 0 or depth > MAX_DEPTH:
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "TYPE_MISMATCH", "message": "depth must be within 0..%d" % MAX_DEPTH, "details": {"expected": "0..%d" % MAX_DEPTH, "got": depth}}},
		}
	var body := layout(root, node as Control, t.path, depth)
	return {"code": 200, "body": {"ok": true, "data": body}}
