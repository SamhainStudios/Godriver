class_name TestDriverAssertionHandler
extends Object
## GTD-032 — Server-side assertion handler (SPEC §5.6).
##
## Evaluates node state on the main thread and returns structured evaluation
## results (passed: true | false) without throwing server-side errors on failure.


## POST /assert/visible — evaluate node visibility in tree / viewport.
static func assert_visible(root: Node, args: Dictionary) -> Dictionary:
	var t := TestDriverInputHandler.resolve_target(root, args)
	if not t.get("ok", false):
		return {"code": t.get("code", 400), "body": {"ok": false, "error": t.get("error", {})}}
	var node: Node = t.get("node")

	var expected: bool = bool(args.get("expected", true))
	var actual: bool = true

	if node is CanvasItem:
		actual = (node as CanvasItem).is_visible_in_tree()
	elif node is Node3D:
		actual = (node as Node3D).visible
	elif node.get("visible") != null:
		actual = bool(node.get("visible"))

	var passed: bool = (actual == expected)

	return {
		"code": 200,
		"body": {
			"ok": true,
			"data": {
				"target": str(t.get("path")),
				"actual": actual,
				"expected": expected,
				"passed": passed
			}
		}
	}


## POST /assert/enabled — evaluate node enabled/disabled state.
static func assert_enabled(root: Node, args: Dictionary) -> Dictionary:
	var t := TestDriverInputHandler.resolve_target(root, args)
	if not t.get("ok", false):
		return {"code": t.get("code", 400), "body": {"ok": false, "error": t.get("error", {})}}
	var node: Node = t.get("node")

	var expected: bool = bool(args.get("expected", true))
	var actual: bool = true

	var listed_disabled := false
	for p in node.get_property_list():
		if p.get("name", "") == "disabled":
			listed_disabled = true
			break

	if listed_disabled:
		actual = not bool(node.get("disabled"))
	elif node.process_mode == Node.PROCESS_MODE_DISABLED:
		actual = false
	else:
		actual = true

	var passed: bool = (actual == expected)

	return {
		"code": 200,
		"body": {
			"ok": true,
			"data": {
				"target": str(t.get("path")),
				"actual": actual,
				"expected": expected,
				"passed": passed
			}
		}
	}


## POST /assert/property — evaluate node property value against expected shape.
static func assert_property(root: Node, args: Dictionary) -> Dictionary:
	var t := TestDriverInputHandler.resolve_target(root, args)
	if not t.get("ok", false):
		return {"code": t.get("code", 400), "body": {"ok": false, "error": t.get("error", {})}}
	var node: Node = t.get("node")

	var prop_name := str(args.get("property", ""))
	if prop_name.is_empty():
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "missing required parameter 'property'"}}
		}

	var listed := false
	for p in node.get_property_list():
		if p.get("name", "") == prop_name:
			listed = true
			break

	if not listed:
		return {
			"code": 404,
			"body": {"ok": false, "error": {"code": "PROPERTY_NOT_FOUND", "message": "node '%s' has no property '%s'" % [str(t.get("path")), prop_name]}}
		}

	var raw_val: Variant = node.get(prop_name)
	var actual: Variant = TestDriverSerializer.encode(raw_val)

	if not args.has("expected"):
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "MISSING_PARAM", "message": "missing required parameter 'expected'"}}
		}

	var expected: Variant = args.get("expected")
	var passed: bool = (actual == expected)

	return {
		"code": 200,
		"body": {
			"ok": true,
			"data": {
				"target": str(t.get("path")),
				"property": prop_name,
				"actual": actual,
				"expected": expected,
				"passed": passed
			}
		}
	}
