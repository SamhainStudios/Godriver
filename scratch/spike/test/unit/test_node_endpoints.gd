extends GdUnitTestSuite
## GTD-013 — node read endpoints (SPEC §5.2): /node/<path> summary shape,
## /node/<path>/property/<name> §4 round-trips, error codes.

const PropsNodeScript := preload("res://scratch/spike/test/fixtures/props_node.gd")

var _server: TestDriverServer
var _fixture: Node


func before_test() -> void:
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()
	# Fixture tree under the test's root: Main > Button(test_id) + Label + Props.
	var main := Node.new()
	main.name = "Gtd013Main"
	var button := Button.new()
	button.name = "Button"
	button.set_meta("test_id", "start_button")
	var label := Label.new()
	label.name = "Label"
	var props: Node = PropsNodeScript.new()
	props.name = "Props"
	main.add_child(button)
	main.add_child(label)
	main.add_child(props)
	_fixture = main
	add_child(_fixture)


func after_test() -> void:
	_server.stop()


func _http_get(path: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {}
	http.request_completed.connect(func(_r, code, _headers, body):
		result.code = code
		result.body = body.get_string_from_utf8())
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path])
	var waited := 0
	while not result.has("code") and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func _data(r: Dictionary) -> Dictionary:
	var body: Dictionary = JSON.parse_string(r.body)
	return body.get("data", {})


## The fixture lives under the test-suite node, not directly under /root —
## build request paths from its actual absolute path.
func _base() -> String:
	return "/node" + String(_fixture.get_path())


func _error(r: Dictionary) -> Dictionary:
	var body: Dictionary = JSON.parse_string(r.body)
	return body.get("error", {})


func test_node_info_shape_button_label_plain_node() -> void:
	var r: Dictionary = await _http_get(_base() + "/Button")
	assert_int(r.get("code", 0)).is_equal(200)
	var d: Dictionary = _data(r)
	assert_str(str(d.get("path"))).is_equal(String(_fixture.get_path()) + "/Button")
	assert_str(str(d.get("name"))).is_equal("Button")
	assert_str(str(d.get("type"))).is_equal("Button")
	assert_str(str(d.get("test_id"))).is_equal("start_button")
	assert_int(int(d.get("child_count", -1))).is_equal(0)
	assert_that(d.get("children")).is_empty()
	assert_that(d.get("script")).is_null()
	# Label: no test_id → null.
	r = await _http_get(_base() + "/Label")
	assert_int(r.get("code", 0)).is_equal(200)
	d = _data(r)
	assert_str(str(d.get("type"))).is_equal("Label")
	assert_that(d.get("test_id")).is_null()
	# Plain Node (the fixture root itself).
	r = await _http_get(_base())
	assert_int(r.get("code", 0)).is_equal(200)
	d = _data(r)
	assert_str(str(d.get("type"))).is_equal("Node")
	assert_int(int(d.get("child_count", -1))).is_equal(3)
	var children: Array = d.get("children", [])
	assert_str(str(children[0])).is_equal("Button")
	assert_str(str(children[1])).is_equal("Label")
	assert_str(str(children[2])).is_equal("Props")


func test_property_reads_roundtrip_per_section4() -> void:
	var base := _base() + "/Props/property"
	# Vector2.
	var r: Dictionary = await _http_get(base + "/v2")
	assert_int(r.get("code", 0)).is_equal(200)
	var d: Dictionary = _data(r)
	assert_str(d.type).is_equal("Vector2")
	assert_float(d.value.x).is_equal(1.0)
	assert_float(d.value.y).is_equal(2.0)
	# Color.
	r = await _http_get(base + "/col")
	d = _data(r)
	assert_str(d.type).is_equal("Color")
	assert_float(d.value.r).is_equal(0.25)
	assert_float(d.value.a).is_equal(1.0)
	# NodePath (serialized as string per §4).
	r = await _http_get(base + "/np")
	d = _data(r)
	assert_str(d.type).is_equal("NodePath")
	assert_str(d.value).is_equal("root/Main/Button")
	# String / bool / int (JSON int arrives as float — compare as float).
	r = await _http_get(base + "/s")
	d = _data(r)
	assert_str(d.type).is_equal("String")
	assert_str(d.value).is_equal("hello")
	r = await _http_get(base + "/b")
	d = _data(r)
	assert_str(d.type).is_equal("bool")
	assert_bool(d.value).is_true()
	r = await _http_get(base + "/i")
	d = _data(r)
	assert_str(d.type).is_equal("int")
	assert_float(d.value).is_equal(7.0)


func test_property_unsupported_type() -> void:
	var props: Node = _fixture.get_node("Props")
	props.fn = Callable(self, "before_test")
	var r: Dictionary = await _http_get(_base() + "/Props/property/fn")
	assert_int(r.get("code", 0)).is_equal(400)
	assert_str(str(_error(r).get("code"))).is_equal("UNSUPPORTED_TYPE")


func test_error_codes() -> void:
	# Unknown node → 404 NODE_NOT_FOUND.
	var r: Dictionary = await _http_get(_base() + "/Nope")
	assert_int(r.get("code", 0)).is_equal(404)
	assert_str(str(_error(r).get("code"))).is_equal("NODE_NOT_FOUND")
	# Existing node, unknown property → 404 PROPERTY_NOT_FOUND.
	r = await _http_get(_base() + "/Button/property/not_a_prop")
	assert_int(r.get("code", 0)).is_equal(404)
	assert_str(str(_error(r).get("code"))).is_equal("PROPERTY_NOT_FOUND")
	# Engine-private property also PROPERTY_NOT_FOUND (§5.2).
	r = await _http_get(_base() + "/Button/property/_private_internal")
	assert_int(r.get("code", 0)).is_equal(404)
	assert_str(str(_error(r).get("code"))).is_equal("PROPERTY_NOT_FOUND")
	# Malformed path → 400 BAD_PATH.
	r = await _http_get("/node/%20")
	assert_int(r.get("code", 0)).is_equal(400)
	assert_str(str(_error(r).get("code"))).is_equal("BAD_PATH")
