class_name TestDriverSerializer
## JSON <-> Variant mapping per SPEC §4 (frozen shapes).
## Canonical §4 implementation (GTD-007 property tests, GTD-013+ handlers).
## Object/Node/Callable/Signal are unsupported in v0.1.
##
## encode(v) -> JSON-ready Variant (dicts/arrays/numbers/strings/bools/null)
## decode(v, type) -> Variant   (type = the declared target Variant.Type;
##                               needed because JSON shapes are ambiguous,
##                               e.g. {x,y,z,w} is Vector4 OR Quaternion)

const META_KEY := "test_id"


static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			if is_nan(v):
				return "NaN"
			if is_inf(v):
				return "Infinity" if v > 0.0 else "-Infinity"
			return v
		TYPE_STRING_NAME:
			return String(v)
		TYPE_NODE_PATH:
			return String(v)
		TYPE_VECTOR2:
			return {"x": v.x, "y": v.y}
		TYPE_VECTOR2I:
			return {"x": v.x, "y": v.y}
		TYPE_VECTOR3:
			return {"x": v.x, "y": v.y, "z": v.z}
		TYPE_VECTOR3I:
			return {"x": v.x, "y": v.y, "z": v.z}
		TYPE_VECTOR4:
			return {"x": v.x, "y": v.y, "z": v.z, "w": v.w}
		TYPE_VECTOR4I:
			return {"x": v.x, "y": v.y, "z": v.z, "w": v.w}
		TYPE_COLOR:
			return {"r": v.r, "g": v.g, "b": v.b, "a": v.a}
		TYPE_RECT2:
			return {"x": v.position.x, "y": v.position.y, "w": v.size.x, "h": v.size.y}
		TYPE_RECT2I:
			return {"x": v.position.x, "y": v.position.y, "w": v.size.x, "h": v.size.y}
		TYPE_QUATERNION:
			return {"x": v.x, "y": v.y, "z": v.z, "w": v.w}
		TYPE_BASIS:
			return {
				"x": {"x": v.x.x, "y": v.x.y, "z": v.x.z},
				"y": {"x": v.y.x, "y": v.y.y, "z": v.y.z},
				"z": {"x": v.z.x, "y": v.z.y, "z": v.z.z},
			}
		TYPE_TRANSFORM2D:
			return {
				"x": {"x": v.x.x, "y": v.x.y},
				"y": {"x": v.y.x, "y": v.y.y},
				"origin": {"x": v.origin.x, "y": v.origin.y},
			}
		TYPE_TRANSFORM3D:
			return {
				"basis": {
					"x": {"x": v.basis.x.x, "y": v.basis.x.y, "z": v.basis.x.z},
					"y": {"x": v.basis.y.x, "y": v.basis.y.y, "z": v.basis.y.z},
					"z": {"x": v.basis.z.x, "y": v.basis.z.y, "z": v.basis.z.z},
				},
				"origin": {"x": v.origin.x, "y": v.origin.y, "z": v.origin.z},
			}
		TYPE_AABB:
			return {
				"position": {"x": v.position.x, "y": v.position.y, "z": v.position.z},
				"size": {"x": v.size.x, "y": v.size.y, "z": v.size.z},
			}
		TYPE_PLANE:
			return {
				"normal": {"x": v.normal.x, "y": v.normal.y, "z": v.normal.z},
				"d": v.d,
			}
		TYPE_ARRAY:
			var out: Array = []
			for item in v:
				out.append(encode(item))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for key in v:
				out[str(key)] = encode(v[key])
			return out
		_:
			# Object/Node/Callable/Signal etc. -> unsupported in v0.1 (SPEC §4).
			push_error("TestDriverSerializer: unsupported type %d" % typeof(v))
			return null


static func decode(v: Variant, type: int) -> Variant:
	match type:
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_STRING:
			return v
		TYPE_INT:
			# JSON has no int/float distinction: parsers deliver 7 as 7.0.
			# Coerce back to int when the target type is int (SPEC §4: int = number).
			if v is float:
				return int(v)
			return v
		TYPE_FLOAT:
			if v is String:
				match v:
					"NaN":
						return NAN
					"Infinity":
						return INF
					"-Infinity":
						return -INF
					_:
						return null
			return float(v)
		TYPE_STRING_NAME:
			return StringName(v)
		TYPE_NODE_PATH:
			return NodePath(v)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			if v is Dictionary and v.has_all(["x", "y"]):
				return Vector2(v["x"], v["y"]) if type == TYPE_VECTOR2 else Vector2i(v["x"], v["y"])
			return null
		TYPE_VECTOR3, TYPE_VECTOR3I:
			if v is Dictionary and v.has_all(["x", "y", "z"]):
				return Vector3(v["x"], v["y"], v["z"]) if type == TYPE_VECTOR3 else Vector3i(v["x"], v["y"], v["z"])
			return null
		TYPE_VECTOR4, TYPE_VECTOR4I:
			if v is Dictionary and v.has_all(["x", "y", "z", "w"]):
				return Vector4(v["x"], v["y"], v["z"], v["w"]) if type == TYPE_VECTOR4 else Vector4i(v["x"], v["y"], v["z"], v["w"])
			return null
		TYPE_COLOR:
			if v is Dictionary and v.has_all(["r", "g", "b", "a"]):
				return Color(v["r"], v["g"], v["b"], v["a"])
			return null
		TYPE_RECT2, TYPE_RECT2I:
			if v is Dictionary and v.has_all(["x", "y", "w", "h"]):
				return Rect2(v["x"], v["y"], v["w"], v["h"]) if type == TYPE_RECT2 else Rect2i(v["x"], v["y"], v["w"], v["h"])
			return null
		TYPE_QUATERNION:
			if v is Dictionary and v.has_all(["x", "y", "z", "w"]):
				return Quaternion(v["x"], v["y"], v["z"], v["w"])
			return null
		TYPE_BASIS:
			if v is Dictionary and v.has_all(["x", "y", "z"]):
				return Basis(
					Vector3(v["x"]["x"], v["x"]["y"], v["x"]["z"]),
					Vector3(v["y"]["x"], v["y"]["y"], v["y"]["z"]),
					Vector3(v["z"]["x"], v["z"]["y"], v["z"]["z"])
				)
			return null
		TYPE_TRANSFORM2D:
			if v is Dictionary and v.has_all(["x", "y", "origin"]):
				return Transform2D(
					Vector2(v["x"]["x"], v["x"]["y"]),
					Vector2(v["y"]["x"], v["y"]["y"]),
					Vector2(v["origin"]["x"], v["origin"]["y"])
				)
			return null
		TYPE_TRANSFORM3D:
			if v is Dictionary and v.has_all(["basis", "origin"]):
				var b: Dictionary = v["basis"]
				return Transform3D(
					Basis(
						Vector3(b["x"]["x"], b["x"]["y"], b["x"]["z"]),
						Vector3(b["y"]["x"], b["y"]["y"], b["y"]["z"]),
						Vector3(b["z"]["x"], b["z"]["y"], b["z"]["z"])
					),
					Vector3(v["origin"]["x"], v["origin"]["y"], v["origin"]["z"])
				)
			return null
		TYPE_AABB:
			if v is Dictionary and v.has_all(["position", "size"]):
				var p: Dictionary = v["position"]
				var s: Dictionary = v["size"]
				return AABB(
					Vector3(p["x"], p["y"], p["z"]),
					Vector3(s["x"], s["y"], s["z"])
				)
			return null
		TYPE_PLANE:
			if v is Dictionary and v.has_all(["normal", "d"]):
				var n: Dictionary = v["normal"]
				return Plane(Vector3(n["x"], n["y"], n["z"]), v["d"])
			return null
		TYPE_ARRAY:
			if v is Array:
				return v.duplicate(true)
			return null
		TYPE_DICTIONARY:
			if v is Dictionary:
				return v.duplicate(true)
			return null
		_:
			return null
