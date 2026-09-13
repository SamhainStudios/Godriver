extends GdUnitTestSuite
## GTD-033 — State endpoints (/state, /state/schema, /state/set)

var _server: TestDriverServer
var _fixture: Node


func before_test() -> void:
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.free()
		_fixture = null
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	_server.stop()
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.free()
		_fixture = null


func _http_get(path: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {"code": 0, "body": ""}
	http.request_completed.connect(func(_r, code, _headers, b):
		result.code = code
		result.body = b.get_string_from_utf8())
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path])
	var waited := 0
	while int(result.code) == 0 and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func _http_post(path: String, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {"code": 0, "body": ""}
	http.request_completed.connect(func(_r, code, _headers, b):
		result.code = code
		result.body = b.get_string_from_utf8())
	var headers := PackedStringArray(["Content-Type: application/json"])
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], headers, HTTPClient.METHOD_POST, body)
	var waited := 0
	while int(result.code) == 0 and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func _parsed(r: Dictionary) -> Dictionary:
	return JSON.parse_string(r.body)


func _make_target_node() -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node

var player_life: int = 100
var player_name: String = "Hero"
var is_active: bool = true
var speed: float = 5.5
var pos: Vector2 = Vector2(10.0, 20.0)
var color: Color = Color(1.0, 0.0, 0.0, 1.0)
var items: Array = ["sword", "shield"]
var extra_obj: Object = null
"""
	script.reload()
	var node := Node.new()
	node.name = "StateFixture"
	node.set_script(script)
	_fixture = node
	get_tree().root.add_child(node)
	return node


func test_state_get_schema_and_set_on_target_node() -> void:
	var node := _make_target_node()
	var path := String(node.get_path())

	# 1. GET /state/schema?target=<path>
	var res_schema := await _http_get("/state/schema?target=" + path)
	assert_int(res_schema.code).is_equal(200)
	var schema_data: Dictionary = _parsed(res_schema).get("data", {})
	assert_str(schema_data.get("target", "")).is_equal(path)
	var props: Array = schema_data.get("properties", [])
	assert_int(props.size()).is_equal(8)

	# 2. POST /state/set on target node
	var set_body := JSON.stringify({
		"target": path,
		"values": {
			"player_life": 150,
			"player_name": "Champion",
			"is_active": false,
			"speed": 12.5,
			"pos": {"x": 30.0, "y": 40.0},
			"items": ["bow", "arrow"]
		}
	})
	var res_set := await _http_post("/state/set", set_body)
	assert_int(res_set.code).is_equal(200)
	var set_data: Dictionary = _parsed(res_set).get("data", {})
	assert_str(set_data.get("target", "")).is_equal(path)
	var updated: Array = set_data.get("updated", [])
	assert_int(updated.size()).is_equal(6)

	# Verify mutated values on object
	assert_int(int(node.get("player_life"))).is_equal(150)
	assert_str(str(node.get("player_name"))).is_equal("Champion")
	assert_bool(bool(node.get("is_active"))).is_false()
	assert_float(float(node.get("speed"))).is_equal(12.5)
	assert_object(node.get("pos")).is_equal(Vector2(30, 40))


func test_coercion_rules_and_string_types() -> void:
	var node := _make_target_node()
	var path := String(node.get_path())

	# String coercion to int/float/bool
	var set_body := JSON.stringify({
		"target": path,
		"values": {
			"player_life": "200",
			"speed": "99.9",
			"is_active": "true"
		}
	})
	var res := await _http_post("/state/set", set_body)
	assert_int(res.code).is_equal(200)
	assert_int(int(node.get("player_life"))).is_equal(200)
	assert_float(float(node.get("speed"))).is_equal(99.9)
	assert_bool(bool(node.get("is_active"))).is_true()


func test_null_write_rules() -> void:
	var node := _make_target_node()
	var path := String(node.get_path())

	# Value type null write -> 400 NULL_NOT_ALLOWED
	var res_val := await _http_post("/state/set", JSON.stringify({
		"target": path,
		"values": {"player_life": null}
	}))
	assert_int(res_val.code).is_equal(400)
	var err_val: Dictionary = _parsed(res_val).get("error", {})
	assert_str(err_val.get("code", "")).is_equal("NULL_NOT_ALLOWED")

	# Nullable type null write -> 200 OK
	var res_obj := await _http_post("/state/set", JSON.stringify({
		"target": path,
		"values": {"extra_obj": null}
	}))
	assert_int(res_obj.code).is_equal(200)


func test_error_responses() -> void:
	var node := _make_target_node()
	var path := String(node.get_path())

	# 404 TARGET_NOT_FOUND
	var res_not_found := await _http_get("/state/schema?target=/root/NonExistentNode")
	assert_int(res_not_found.code).is_equal(404)
	assert_str(_parsed(res_not_found).get("error", {}).get("code", "")).is_equal("TARGET_NOT_FOUND")

	# 400 UNKNOWN_KEY
	var res_unknown := await _http_post("/state/set", JSON.stringify({
		"target": path,
		"values": {"invalid_property": 123}
	}))
	assert_int(res_unknown.code).is_equal(400)
	assert_str(_parsed(res_unknown).get("error", {}).get("code", "")).is_equal("UNKNOWN_KEY")

	# 400 TYPE_MISMATCH
	var res_mismatch := await _http_post("/state/set", JSON.stringify({
		"target": path,
		"values": {"player_life": "not_an_int"}
	}))
	assert_int(res_mismatch.code).is_equal(400)
	assert_str(_parsed(res_mismatch).get("error", {}).get("code", "")).is_equal("TYPE_MISMATCH")

	# 400 MISSING_PARAM
	var res_missing := await _http_post("/state/set", JSON.stringify({"target": path}))
	assert_int(res_missing.code).is_equal(400)
	assert_str(_parsed(res_missing).get("error", {}).get("code", "")).is_equal("MISSING_PARAM")


func test_dictionary_int_key_coercion() -> void:
	var script := GDScript.new()
	script.source_code = """
extends Node
var inventories: Dictionary = {0: ["theremin"]}
"""
	script.reload()
	var node := Node.new()
	node.name = "DictFixture"
	node.set_script(script)
	_fixture = node
	get_tree().root.add_child(node)
	var path := String(node.get_path())

	# POST string keys from JSON {"0": ["key", "map"], "1": ["lantern"]}
	var res := await _http_post("/state/set", JSON.stringify({
		"target": path,
		"values": {
			"inventories": {
				"0": ["key", "map"],
				"1": ["lantern"]
			}
		}
	}))
	assert_int(res.code).is_equal(200)
	var inv: Dictionary = node.get("inventories")
	assert_bool(inv.has(0)).is_true()
	assert_bool(inv.has(1)).is_true()
	assert_bool(inv.has("0")).is_false()
	assert_array(inv[0]).is_equal(["key", "map"])
	assert_array(inv[1]).is_equal(["lantern"])

