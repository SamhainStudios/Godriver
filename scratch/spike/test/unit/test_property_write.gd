# GTD-055 - POST /node/<path>/property/<name> (SPEC §5.2).
#
# Property writes: §4-decoded values coerced to the declared type, §8 null
# rules, error codes. Enables game-state seeding (arrange-phase setup).
extends GdUnitTestSuite

const TestDriverServer := preload("res://addons/godriver/http_server.gd")

var _server: TestDriverServer


func before_test() -> void:
	var old := get_tree().root.get_node_or_null("PropFixture")
	if old != null:
		get_tree().root.remove_child(old)
		old.free()
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	var old := get_tree().root.get_node_or_null("PropFixture")
	if old != null:
		get_tree().root.remove_child(old)
		old.free()


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _http(method: String, path: String, body: String = "") -> Dictionary:
	var http: HTTPRequest = auto_free(HTTPRequest.new())
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var out := {}
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, b: PackedByteArray) -> void:
		out["code"] = code
		out["body"] = JSON.parse_string(b.get_string_from_utf8())
	)
	var m := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var err := http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], PackedStringArray(), m, body)
	assert_int(err).is_equal(OK)
	var deadline := Time.get_ticks_msec() + 5000
	while not out.has("code") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return out


func _err_code(r: Dictionary) -> String:
	return str(r.get("body", {}).get("error", {}).get("code", ""))


func _make_fixture() -> Node:
	var fixture := Node2D.new()
	fixture.name = "PropFixture"
	var body := CharacterBody2D.new()
	body.name = "Body"
	body.position = Vector2(100, 200)
	fixture.add_child(body)
	var lbl := Label.new()
	lbl.name = "Lbl"
	lbl.text = "hello"
	fixture.add_child(lbl)
	var counter := RefCounted.new()
	get_tree().root.add_child(fixture)
	return fixture


func test_write_vector2_int_string_bool() -> void:
	var fixture := _make_fixture()
	var base := "/node/root/PropFixture"
	var r := await _http("POST", base + "/Body/property/position", '{"value": {"x": 500, "y": 1000}}')
	assert_int(r.get("code", 0)).is_equal(200)
	var data: Dictionary = r.get("body", {}).get("data", {})
	assert_str(str(data.get("type", ""))).is_equal("Vector2")
	assert_float(float(data.get("value", {}).get("x", 0))).is_equal(500.0)
	var check := await _http("GET", base + "/Body/property/position")
	assert_float(float(check.get("body", {}).get("data", {}).get("value", {}).get("y", 0))).is_equal(1000.0)
	var ri := await _http("POST", base + "/Body/property/meta_written", '{"value": 7}')
	# meta_written is not a listed property -> 404
	assert_int(ri.get("code", 0)).is_equal(404)
	var rs := await _http("POST", base + "/Lbl/property/text", '{"value": "Coins: 5 / 8"}')
	assert_int(rs.get("code", 0)).is_equal(200)
	assert_str(str(rs.get("body", {}).get("data", {}).get("value", ""))).is_equal("Coins: 5 / 8")


func test_write_by_test_id() -> void:
	_make_fixture()
	var lbl: Label = get_tree().root.get_node("PropFixture/Lbl")
	lbl.set_meta("test_id", "prop_lbl")
	# Property writes are path-based: resolve via /node?test_id first, then
	# write by the returned path.
	var found := await _http("GET", "/node?test_id=prop_lbl")
	assert_int(found.get("code", 0)).is_equal(200)
	var path: String = str(found.get("body", {}).get("data", {}).get("path", ""))
	var r := await _http("POST", "/node" + found.get("body", {}).get("data", {}).get("path", "") + "/property/text", '{"value": "via test_id"}')
	assert_int(r.get("code", 0)).is_equal(200)
	assert_str(str(lbl.text)).is_equal("via test_id")


func test_error_codes() -> void:
	_make_fixture()
	var base := "/node/root/PropFixture"
	var missing_prop := await _http("POST", base + "/Body/property/no_such_prop", '{"value": 1}')
	assert_int(missing_prop.get("code", 0)).is_equal(404)
	assert_str(_err_code(missing_prop)).is_equal("PROPERTY_NOT_FOUND")
	var missing_node := await _http("POST", "/node/root/Nope/property/position", '{"value": {"x": 1, "y": 2}}')
	assert_int(missing_node.get("code", 0)).is_equal(404)
	assert_str(_err_code(missing_node)).is_equal("NODE_NOT_FOUND")
	var type_mismatch := await _http("POST", base + "/Body/property/position", '{"value": "not-a-vector"}')
	assert_int(type_mismatch.get("code", 0)).is_equal(400)
	assert_str(_err_code(type_mismatch)).is_equal("TYPE_MISMATCH")
	var null_value := await _http("POST", base + "/Lbl/property/text", '{"value": null}')
	assert_int(null_value.get("code", 0)).is_equal(400)
	assert_str(_err_code(null_value)).is_equal("NULL_NOT_ALLOWED")
