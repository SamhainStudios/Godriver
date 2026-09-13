class_name TestDriverStateHandler
extends RefCounted
## GTD-015 / GTD-033 — State endpoints (/state, /state/schema, /state/set).
## SPEC §5.8 and §8 implementation.

const STATE_AUTOLOAD_SETTING := "godriver/state_autoload"
const DEFAULT_STATE_AUTOLOAD := "GameState"


static func _resolve_target(tree: SceneTree, target: String) -> Dictionary:
	target = target.uri_decode()
	if target.is_empty():
		var autoload_name := str(ProjectSettings.get_setting(STATE_AUTOLOAD_SETTING, DEFAULT_STATE_AUTOLOAD))
		var state: Node = tree.root.get_node_or_null(NodePath("/root/" + autoload_name))
		if state == null:
			return {
				"code": 409,
				"body": {
					"ok": false,
					"error": {
						"code": "STATE_AUTOLOAD_MISSING",
						"message": "state autoload '%s' is not in the tree" % autoload_name,
						"details": {
							"hint": "set project setting '%s' to your state autoload's name, or add an autoload named '%s'" % [STATE_AUTOLOAD_SETTING, autoload_name]
						}
					}
				}
			}
		return {"ok": true, "obj": state, "label_key": "autoload", "label_val": autoload_name}

	var obj: Object = null
	if target.begins_with("res://"):
		if ResourceLoader.exists(target):
			obj = ResourceLoader.load(target)
	elif target.begins_with("/"):
		obj = tree.root.get_node_or_null(NodePath(target))
	else:
		obj = tree.root.get_node_or_null(NodePath("/root/" + target))
		if obj == null:
			obj = tree.root.get_node_or_null(NodePath(target))

	if obj == null:
		return {
			"code": 404,
			"body": {
				"ok": false,
				"error": {
					"code": "TARGET_NOT_FOUND",
					"message": "target '%s' could not be resolved" % target,
					"details": {"target": target}
				}
			}
		}
	return {"ok": true, "obj": obj, "label_key": "target", "label_val": target}


static func _get_script_properties(obj: Object) -> Dictionary:
	var props := {}
	for p in obj.get_property_list():
		var usage: int = p.get("usage", 0)
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var pname: String = p.get("name", "")
			props[pname] = p
	return props


static func _type_to_spec_string(type_id: int) -> String:
	match type_id:
		TYPE_NIL: return "Variant"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR2I: return "Vector2i"
		TYPE_RECT2: return "Rect2"
		TYPE_RECT2I: return "Rect2i"
		TYPE_VECTOR3: return "Vector3"
		TYPE_VECTOR3I: return "Vector3i"
		TYPE_VECTOR4: return "Vector4"
		TYPE_VECTOR4I: return "Vector4i"
		TYPE_COLOR: return "Color"
		TYPE_NODE_PATH: return "NodePath"
		TYPE_OBJECT: return "Object"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_:
			var s := type_string(type_id)
			return s if not s.is_empty() else "Variant"


static func read_state(tree: SceneTree, args: Dictionary = {}) -> Dictionary:
	var target := str(args.get("target", ""))
	var res := _resolve_target(tree, target)
	if res.has("code"):
		return res
	var obj: Object = res.obj
	var label_key: String = res.label_key
	var label_val: String = res.label_val

	var values := {}
	var prop_map := _get_script_properties(obj)
	for prop_name in prop_map:
		values[prop_name] = TestDriverSerializer.encode(obj.get(prop_name))
	return {
		"code": 200,
		"body": {"ok": true, "data": {label_key: label_val, "values": values}},
	}


static func get_schema(tree: SceneTree, args: Dictionary = {}) -> Dictionary:
	var target := str(args.get("target", ""))
	var res := _resolve_target(tree, target)
	if res.has("code"):
		return res
	var obj: Object = res.obj
	var label_key: String = res.label_key
	var label_val: String = res.label_val

	var properties := []
	var prop_map := _get_script_properties(obj)
	for prop_name in prop_map:
		var pinfo: Dictionary = prop_map[prop_name]
		var type_id: int = pinfo.get("type", 0)
		var type_str := _type_to_spec_string(type_id)
		var encoded_val: Variant = TestDriverSerializer.encode(obj.get(prop_name))
		properties.append({
			"name": prop_name,
			"type": type_str,
			"value": encoded_val,
		})

	return {
		"code": 200,
		"body": {"ok": true, "data": {label_key: label_val, "properties": properties}},
	}


static func set_state(tree: SceneTree, args: Dictionary = {}) -> Dictionary:
	if not args.has("values") or not (args["values"] is Dictionary):
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "MISSING_PARAM",
					"message": "missing or invalid 'values' dictionary",
					"details": {"param": "values"}
				}
			}
		}
	var values: Dictionary = args["values"]
	var target := str(args.get("target", ""))
	var res := _resolve_target(tree, target)
	if res.has("code"):
		return res
	var obj: Object = res.obj
	var label_key: String = res.label_key
	var label_val: String = res.label_val

	var prop_map := _get_script_properties(obj)
	var coerced_values := {}
	var updated_keys := []

	for key_raw in values:
		var key := str(key_raw)
		if not prop_map.has(key):
			return {
				"code": 400,
				"body": {
					"ok": false,
					"error": {
						"code": "UNKNOWN_KEY",
						"message": "property '%s' does not exist on target" % key,
						"details": {"valid_keys": prop_map.keys()}
					}
				}
			}
		var pinfo: Dictionary = prop_map[key]
		var raw_val: Variant = values[key_raw]
		var coercion_res := _coerce_value(key, pinfo, raw_val, obj)
		if not coercion_res.ok:
			return {
				"code": coercion_res.code,
				"body": {
					"ok": false,
					"error": {
						"code": coercion_res.error_code,
						"message": coercion_res.message,
						"details": coercion_res.details
					}
				}
			}
		coerced_values[key] = coercion_res.value
		updated_keys.append(key)

	# All valid -> apply mutations
	for key in coerced_values:
		obj.set(key, coerced_values[key])

	return {
		"code": 200,
		"body": {"ok": true, "data": {label_key: label_val, "updated": updated_keys}},
	}


static func _coerce_value(key: String, pinfo: Dictionary, raw_val: Variant, obj: Object = null) -> Dictionary:
	var target_type: int = pinfo.get("type", 0)
	var type_name := _type_to_spec_string(target_type)

	# Null handling (SPEC §8)
	if raw_val == null:
		if target_type == TYPE_NIL or target_type == TYPE_OBJECT:
			return {"ok": true, "value": null}
		else:
			return {
				"ok": false,
				"code": 400,
				"error_code": "NULL_NOT_ALLOWED",
				"message": "null write rejected for value type property '%s'" % key,
				"details": {"property": key, "expected": type_name}
			}

	match target_type:
		TYPE_INT:
			if raw_val is int:
				return {"ok": true, "value": raw_val}
			elif raw_val is float:
				if raw_val == floor(raw_val):
					return {"ok": true, "value": int(raw_val)}
				else:
					return _type_mismatch(key, type_name, "float (non-integral: %s)" % raw_val)
			elif raw_val is String:
				if String(raw_val).is_valid_int():
					return {"ok": true, "value": String(raw_val).to_int()}
				else:
					return _type_mismatch(key, type_name, "String (\"%s\")" % raw_val)
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_FLOAT:
			if raw_val is float or raw_val is int:
				return {"ok": true, "value": float(raw_val)}
			elif raw_val is String:
				if String(raw_val).is_valid_float():
					return {"ok": true, "value": String(raw_val).to_float()}
				else:
					return _type_mismatch(key, type_name, "String (\"%s\")" % raw_val)
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_BOOL:
			if raw_val is bool:
				return {"ok": true, "value": raw_val}
			elif raw_val is String:
				var s := String(raw_val).to_lower()
				if s == "true":
					return {"ok": true, "value": true}
				elif s == "false":
					return {"ok": true, "value": false}
				else:
					return _type_mismatch(key, type_name, "String (\"%s\")" % raw_val)
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_STRING, TYPE_STRING_NAME:
			if raw_val is String or raw_val is StringName:
				return {"ok": true, "value": str(raw_val)}
			elif raw_val is int or raw_val is float or raw_val is bool:
				return {"ok": true, "value": str(raw_val)}
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_VECTOR2, TYPE_VECTOR2I:
			if raw_val is Array:
				var arr: Array = raw_val
				if arr.size() == 2 and (arr[0] is int or arr[0] is float) and (arr[1] is int or arr[1] is float):
					var v2 := Vector2(float(arr[0]), float(arr[1]))
					return {"ok": true, "value": v2 if target_type == TYPE_VECTOR2 else Vector2i(v2)}
				return _type_mismatch(key, type_name, "Array (invalid arity or types)")
			elif raw_val is Dictionary:
				var d: Dictionary = raw_val
				if d.has_all(["x", "y"]) and (d["x"] is int or d["x"] is float) and (d["y"] is int or d["y"] is float):
					var v2 := Vector2(float(d["x"]), float(d["y"]))
					return {"ok": true, "value": v2 if target_type == TYPE_VECTOR2 else Vector2i(v2)}
				return _type_mismatch(key, type_name, "Dictionary (missing or invalid x, y)")
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_VECTOR3, TYPE_VECTOR3I:
			if raw_val is Array:
				var arr: Array = raw_val
				if arr.size() == 3 and (arr[0] is int or arr[0] is float) and (arr[1] is int or arr[1] is float) and (arr[2] is int or arr[2] is float):
					var v3 := Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
					return {"ok": true, "value": v3 if target_type == TYPE_VECTOR3 else Vector3i(v3)}
				return _type_mismatch(key, type_name, "Array (invalid arity or types)")
			elif raw_val is Dictionary:
				var d: Dictionary = raw_val
				if d.has_all(["x", "y", "z"]) and (d["x"] is int or d["x"] is float) and (d["y"] is int or d["y"] is float) and (d["z"] is int or d["z"] is float):
					var v3 := Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
					return {"ok": true, "value": v3 if target_type == TYPE_VECTOR3 else Vector3i(v3)}
				return _type_mismatch(key, type_name, "Dictionary (missing or invalid x, y, z)")
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_COLOR:
			if raw_val is Dictionary:
				var d: Dictionary = raw_val
				if d.has_all(["r", "g", "b", "a"]):
					var r: float = float(d["r"])
					var g: float = float(d["g"])
					var b: float = float(d["b"])
					var a: float = float(d["a"])
					if r < 0.0 or r > 1.0 or g < 0.0 or g > 1.0 or b < 0.0 or b > 1.0 or a < 0.0 or a > 1.0:
						return _type_mismatch(key, type_name, "Color component out of range 0.0..1.0")
					return {"ok": true, "value": Color(r, g, b, a)}
				return _type_mismatch(key, type_name, "Dictionary (missing r, g, b, a)")
			elif raw_val is String:
				var s := String(raw_val)
				if s.begins_with("#"):
					return {"ok": true, "value": Color.html(s)}
				return _type_mismatch(key, type_name, "String (invalid hex color format)")
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_NODE_PATH:
			if raw_val is String or raw_val is NodePath:
				return {"ok": true, "value": NodePath(str(raw_val))}
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_ARRAY:
			if raw_val is Array:
				return {"ok": true, "value": (raw_val as Array).duplicate(true)}
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_DICTIONARY:
			if raw_val is Dictionary:
				var dict_val: Dictionary = (raw_val as Dictionary).duplicate(true)
				var ref_val: Variant = obj.get(key) if obj != null else null
				var ref_dict: Dictionary = ref_val if ref_val is Dictionary else {}
				dict_val = _coerce_dict_keys(dict_val, ref_dict)
				return {"ok": true, "value": dict_val}
			else:
				return _type_mismatch(key, type_name, typeof(raw_val))

		TYPE_NIL, TYPE_OBJECT:
			var decoded: Variant = TestDriverSerializer.decode(raw_val, target_type)
			if decoded != null or raw_val == null:
				return {"ok": true, "value": decoded}
			else:
				return {"ok": true, "value": raw_val}

		_:
			return {"ok": true, "value": raw_val}


## Auto-coerce JSON string keys into GDScript int keys when appropriate (Bug #6).
## Converts keys if the reference dictionary has int keys, or if all incoming
## keys are valid integer strings (e.g. "0", "1").
static func _coerce_dict_keys(incoming: Dictionary, reference: Dictionary = {}) -> Dictionary:
	var should_convert := false
	if not reference.is_empty():
		for k in reference:
			if k is int:
				should_convert = true
				break
	else:
		var all_int_keys := true
		for k in incoming:
			if not (k is int or (k is String and String(k).is_valid_int())):
				all_int_keys = false
				break
		if all_int_keys and not incoming.is_empty():
			should_convert = true

	if not should_convert:
		return incoming

	var result := {}
	for k in incoming:
		var new_key: Variant = k
		if k is String and String(k).is_valid_int():
			new_key = String(k).to_int()
		var v: Variant = incoming[k]
		if v is Dictionary:
			var ref_sub: Dictionary = reference.get(new_key, {}) if reference.get(new_key) is Dictionary else {}
			v = _coerce_dict_keys(v as Dictionary, ref_sub)
		result[new_key] = v
	return result


static func _type_mismatch(key: String, expected: String, got: Variant) -> Dictionary:
	var got_str := str(got) if not (got is int) else type_string(got)
	return {
		"ok": false,
		"code": 400,
		"error_code": "TYPE_MISMATCH",
		"message": "property '%s' expected %s, got %s" % [key, expected, got_str],
		"details": {"property": key, "expected": expected, "got": got_str}
	}
