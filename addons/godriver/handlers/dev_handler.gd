class_name TestDriverDevHandler
extends RefCounted
## GTD-034 — Determinism endpoints (/dev/seed, /dev/time_scale, /dev/pause, /dev/save/load).
## SPEC §5.9 and §9 implementation.


static func seed_rng(args: Dictionary) -> Dictionary:
	if not args.has("seed"):
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "MISSING_PARAM",
					"message": "missing required parameter 'seed'",
					"details": {"param": "seed"}
				}
			}
		}
	var raw: Variant = args["seed"]
	var s_val: int = 0
	if raw is int:
		s_val = raw
	elif raw is float:
		if raw == floor(raw):
			s_val = int(raw)
		else:
			return _type_mismatch("seed", "int", "float (non-integral: %s)" % raw)
	elif raw is String and String(raw).is_valid_int():
		s_val = String(raw).to_int()
	else:
		return _type_mismatch("seed", "int", raw)

	seed(s_val)
	return {
		"code": 200,
		"body": {"ok": true, "data": {"seeded": true, "seed": s_val}},
	}


static func set_time_scale(args: Dictionary) -> Dictionary:
	if not args.has("scale"):
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "MISSING_PARAM",
					"message": "missing required parameter 'scale'",
					"details": {"param": "scale"}
				}
			}
		}
	var raw: Variant = args["scale"]
	var scale_val: float = -1.0
	if raw is float or raw is int:
		scale_val = float(raw)
	elif raw is String and String(raw).is_valid_float():
		scale_val = String(raw).to_float()
	else:
		return _type_mismatch("scale", "float", raw)

	if scale_val < 0.0 or scale_val > 1000.0:
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "TYPE_MISMATCH",
					"message": "scale must be between 0.0 and 1000.0",
					"details": {"param": "scale", "expected": "0.0..1000.0", "got": scale_val}
				}
			}
		}

	Engine.time_scale = scale_val
	return {
		"code": 200,
		"body": {"ok": true, "data": {"time_scale": scale_val}},
	}


static func set_pause(tree: SceneTree, args: Dictionary) -> Dictionary:
	if not args.has("enabled"):
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "MISSING_PARAM",
					"message": "missing required parameter 'enabled'",
					"details": {"param": "enabled"}
				}
			}
		}
	var raw: Variant = args["enabled"]
	var pause_val: bool = false
	if raw is bool:
		pause_val = raw
	elif raw is String:
		var s := String(raw).to_lower()
		if s == "true":
			pause_val = true
		elif s == "false":
			pause_val = false
		else:
			return _type_mismatch("enabled", "bool", raw)
	else:
		return _type_mismatch("enabled", "bool", raw)

	tree.paused = pause_val
	return {
		"code": 200,
		"body": {"ok": true, "data": {"paused": pause_val}},
	}


static func save_load(args: Dictionary) -> Dictionary:
	if not args.has("slot"):
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "MISSING_PARAM",
					"message": "missing required parameter 'slot'",
					"details": {"param": "slot"}
				}
			}
		}
	var slot := str(args["slot"]).strip_edges()
	if slot.is_empty():
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "MISSING_PARAM",
					"message": "slot cannot be empty",
					"details": {"param": "slot"}
				}
			}
		}

	var user_path := "user://" + slot + ".save"
	var fixture_path := "res://fixtures/" + slot + ".save"

	if FileAccess.file_exists(user_path):
		return {
			"code": 200,
			"body": {"ok": true, "data": {"slot": slot, "loaded": true, "path": user_path}},
		}
	elif FileAccess.file_exists(fixture_path):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.copy(fixture_path, user_path)
		return {
			"code": 200,
			"body": {"ok": true, "data": {"slot": slot, "loaded": true, "path": user_path, "copied_from_fixture": true}},
		}

	return {
		"code": 404,
		"body": {
			"ok": false,
			"error": {
				"code": "FILE_NOT_FOUND",
				"message": "save slot file '%s' does not exist" % slot,
				"details": {"slot": slot, "expected_path": user_path}
			}
		}
	}


static func _type_mismatch(param: String, expected: String, got: Variant) -> Dictionary:
	var got_str := str(got) if not (got is int) else type_string(got)
	return {
		"code": 400,
		"body": {
			"ok": false,
			"error": {
				"code": "TYPE_MISMATCH",
				"message": "parameter '%s' expected %s, got %s" % [param, expected, got_str],
				"details": {"param": param, "expected": expected, "got": got_str}
			}
		}
	}
