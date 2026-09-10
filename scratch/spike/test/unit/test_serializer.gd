extends GdUnitTestSuite
## GTD-007: serializer round-trip tests (SPEC §4 frozen shapes).
## Round-trip path: encode -> JSON.stringify -> JSON.parse -> decode(target type)
## and assert semantic equality (never byte equality — SPEC §4 NodePath note).

const Serializer := preload("res://addons/godriver/serializer.gd")


func _roundtrip(v: Variant, type: int) -> Variant:
	var encoded: Variant = Serializer.encode(v)
	assert_that(encoded).is_not_null()
	var text := JSON.stringify(encoded)
	var parsed: Variant = JSON.parse_string(text)
	assert_that(parsed).is_not_null()
	return Serializer.decode(parsed, type)


func test_scalars_roundtrip() -> void:
	assert_bool(_roundtrip(true, TYPE_BOOL)).is_true()
	assert_int(_roundtrip(7, TYPE_INT)).is_equal(7)
	assert_float(_roundtrip(2.5, TYPE_FLOAT)).is_equal(2.5)
	assert_str(_roundtrip("hello", TYPE_STRING)).is_equal("hello")
	assert_str(_roundtrip(StringName("sn"), TYPE_STRING_NAME)).is_equal("sn")
	assert_that(_roundtrip(NodePath("/root/Main"), TYPE_NODE_PATH)).is_equal(NodePath("/root/Main"))
	# null round-trips as null (asserted directly — the _roundtrip helper's
	# not-null guards don't apply to a legitimate null payload).
	assert_that(Serializer.encode(null)).is_null()
	assert_that(Serializer.decode(null, TYPE_NIL)).is_null()


func test_special_floats_serialize_as_strings() -> void:
	var nan_encoded: Variant = Serializer.encode(NAN)
	assert_str(nan_encoded).is_equal("NaN")
	assert_bool(is_nan(Serializer.decode("NaN", TYPE_FLOAT))).is_true()
	assert_str(Serializer.encode(INF)).is_equal("Infinity")
	assert_str(Serializer.encode(-INF)).is_equal("-Infinity")
	assert_that(Serializer.decode("Infinity", TYPE_FLOAT)).is_equal(INF)
	assert_that(Serializer.decode("-Infinity", TYPE_FLOAT)).is_equal(-INF)


func test_vectors_roundtrip() -> void:
	assert_that(_roundtrip(Vector2(1.5, -2), TYPE_VECTOR2)).is_equal(Vector2(1.5, -2))
	assert_that(_roundtrip(Vector3(1, 2, 3), TYPE_VECTOR3)).is_equal(Vector3(1, 2, 3))
	assert_that(_roundtrip(Vector4(1, 2, 3, 4), TYPE_VECTOR4)).is_equal(Vector4(1, 2, 3, 4))
	assert_that(_roundtrip(Vector2i(3, 4), TYPE_VECTOR2I)).is_equal(Vector2i(3, 4))
	assert_that(_roundtrip(Vector3i(3, 4, 5), TYPE_VECTOR3I)).is_equal(Vector3i(3, 4, 5))
	assert_that(_roundtrip(Vector4i(3, 4, 5, 6), TYPE_VECTOR4I)).is_equal(Vector4i(3, 4, 5, 6))


func test_color_roundtrip() -> void:
	var c := Color(0.25, 0.5, 0.75, 1.0)
	assert_that(_roundtrip(c, TYPE_COLOR)).is_equal(c)


func test_rect_quaternion_basis_transforms_roundtrip() -> void:
	assert_that(_roundtrip(Rect2(1, 2, 3, 4), TYPE_RECT2)).is_equal(Rect2(1, 2, 3, 4))
	assert_that(_roundtrip(Rect2i(1, 2, 3, 4), TYPE_RECT2I)).is_equal(Rect2i(1, 2, 3, 4))
	assert_that(_roundtrip(Quaternion(0.1, 0.2, 0.3, 0.4), TYPE_QUATERNION)).is_equal(Quaternion(0.1, 0.2, 0.3, 0.4))
	assert_that(_roundtrip(Basis(Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 3)), TYPE_BASIS)).is_equal(Basis(Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 3)))
	assert_that(_roundtrip(Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(5, 6)), TYPE_TRANSFORM2D)).is_equal(Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(5, 6)))
	assert_that(_roundtrip(Transform3D(Basis.IDENTITY, Vector3(7, 8, 9)), TYPE_TRANSFORM3D)).is_equal(Transform3D(Basis.IDENTITY, Vector3(7, 8, 9)))
	assert_that(_roundtrip(AABB(Vector3(0, 0, 0), Vector3(1, 1, 1)), TYPE_AABB)).is_equal(AABB(Vector3(0, 0, 0), Vector3(1, 1, 1)))
	assert_that(_roundtrip(Plane(Vector3(0, 1, 0), 1.5), TYPE_PLANE)).is_equal(Plane(Vector3(0, 1, 0), 1.5))


func test_containers_roundtrip() -> void:
	# JSON fidelity semantics (SPEC §4): nested typed values stay encoded dicts
	# unless decoded with an explicit per-element type; ints arrive as floats.
	var arr := [1, "two", Vector2(1, 2), null]
	var arr_rt: Variant = _roundtrip(arr, TYPE_ARRAY)
	assert_int(arr_rt.size()).is_equal(4)
	# JSON fidelity: ints arrive as floats (1 -> 1.0); GdUnit compares typed,
	# so assert numerically via assert_float.
	assert_float(arr_rt[0]).is_equal(1.0)
	assert_str(arr_rt[1]).is_equal("two")
	assert_that(arr_rt[2]).is_equal({"x": 1.0, "y": 2.0})
	assert_that(arr_rt[3]).is_null()
	# Explicit per-element decode restores the typed value:
	assert_that(Serializer.decode(arr_rt[2], TYPE_VECTOR2)).is_equal(Vector2(1, 2))

	var dict := {"int": 1, "vec": Vector3(1, 2, 3), "nested": {"a": [true, null]}}
	var dict_rt: Variant = _roundtrip(dict, TYPE_DICTIONARY)
	assert_float(dict_rt["int"]).is_equal(1.0)
	assert_that(dict_rt["vec"]).is_equal({"x": 1.0, "y": 2.0, "z": 3.0})
	assert_that(dict_rt["nested"]["a"]).is_equal([true, null])
	assert_that(Serializer.decode(dict_rt["vec"], TYPE_VECTOR3)).is_equal(Vector3(1, 2, 3))


func test_non_string_dictionary_keys_are_stringified() -> void:
	var dict := {3: "three"}
	var encoded: Variant = Serializer.encode(dict)
	assert_str(encoded.keys()[0]).is_equal("3")


func test_unsupported_types_return_null() -> void:
	assert_that(Serializer.encode(Callable(self, "test_scalars_roundtrip"))).is_null()
