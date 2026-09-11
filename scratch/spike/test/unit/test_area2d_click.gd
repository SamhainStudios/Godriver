extends GdUnitTestSuite
## GTD-030 — POST /input/click physics-picking path (SPEC §5.3/§6):
## CollisionObject2D targets (Area2D hotspots). Covers signal delivery via
## physics picking, test_id targeting, shape-geometry click points,
## PICKING_DISABLED, and the unchanged BAD_TARGET for plain Node2D.

var _server: TestDriverServer
var _fixture: Node


func before_test() -> void:
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.queue_free()
		await get_tree().process_frame
	var w: Variant = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h: Variant = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	get_tree().root.size = Vector2i(int(w), int(h))
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	_server.stop()


func _http_post(path: String, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {}
	http.request_completed.connect(func(_r, code, _headers, b):
		result.code = code
		result.body = b.get_string_from_utf8())
	var headers := PackedStringArray(["Content-Type: application/json"])
	http.request("http://127.0.0.1:%d%s" % [_server.bound_port, path], headers, HTTPClient.METHOD_POST, body)
	var waited := 0
	while not result.has("code") and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func _parsed(r: Dictionary) -> Dictionary:
	return JSON.parse_string(r.body)


func _error(r: Dictionary) -> Dictionary:
	return _parsed(r).get("error", {})


## Wait N physics frames — picking consumes queued events on physics frames
## (scene_tree.cpp:652, _picking_viewports group).
func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Area2D hotspot fixture with signal counters. GDScript lambdas capture
## outer locals BY VALUE — counters live in a Dictionary (reference type).
class Hotspot extends Area2D:
	func _init() -> void:
		input_event.connect(_on_input_event)
		mouse_entered.connect(_on_mouse_entered)

	func _on_input_event(_vp: Node, event: InputEvent, _shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed:
			hits()["input_event"] += 1

	func _on_mouse_entered() -> void:
		hits()["mouse_entered"] += 1

	## Counters live in a meta Dictionary (reference type) so signal
	## connections observe mutations; set by the factory before add_child.
	func hits() -> Dictionary:
		return get_meta("hits", {"input_event": 0, "mouse_entered": 0, "last_pos": Vector2.ZERO})


func _make_hotspot(hotspot_name: String, pos: Vector2, shape: Shape2D) -> Hotspot:
	var area := Hotspot.new()
	area.name = hotspot_name
	area.position = pos
	area.set_meta("hits", {"input_event": 0, "mouse_entered": 0, "last_pos": Vector2.ZERO})
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	cs.shape = shape
	area.add_child(cs)
	return area


func _make_fixture() -> Node:
	var fx := Node2D.new()
	fx.name = "Area2dFixture"
	var rect_area := _make_hotspot("RectArea", Vector2(300, 200), RectangleShape2D.new())
	(rect_area.get_node("Shape").shape as RectangleShape2D).size = Vector2(120, 80)
	var circle_area := _make_hotspot("CircleArea", Vector2(600, 200), CircleShape2D.new())
	(circle_area.get_node("Shape").shape as CircleShape2D).radius = 50.0
	var poly := ConvexPolygonShape2D.new()
	poly.points = PackedVector2Array([Vector2(-40, -30), Vector2(40, -30), Vector2(40, 30), Vector2(-40, 30)])
	var poly_area := _make_hotspot("PolyArea", Vector2(300, 400), poly)
	var bare := Hotspot.new()
	bare.name = "BareArea"
	bare.position = Vector2(800, 300)
	fx.add_child(rect_area)
	fx.add_child(circle_area)
	fx.add_child(poly_area)
	fx.add_child(bare)
	_fixture = fx
	add_child(fx)
	return fx


func _hits(fx: Node, hotspot_name: String) -> Dictionary:
	return (fx.get_node(hotspot_name) as Hotspot).get_meta("hits")


func _base(fx: Node, hotspot_name: String) -> String:
	return "%s/%s" % [String(fx.get_path()), hotspot_name]


func test_click_area2d_fires_input_event_and_mouse_entered() -> void:
	var fx := _make_fixture()
	var r := await _http_post("/input/click", '{"path": "%s"}' % _base(fx, "RectArea"))
	assert_int(r.code).is_equal(200)
	var data: Dictionary = _parsed(r).get("data", {})
	assert_bool(data.get("injected", false)).is_true()
	assert_str(str(data.get("mode", ""))).is_equal("picking")
	# Picking consumes queued events on physics frames — wait for them.
	await _wait_physics(3)
	var hits := _hits(fx, "RectArea")
	assert_int(hits["input_event"]).is_greater_equal(1)
	assert_int(hits["mouse_entered"]).is_greater_equal(1)


func test_click_area2d_by_test_id() -> void:
	var fx := _make_fixture()
	var area := fx.get_node("CircleArea")
	area.set_meta("test_id", "circle_hotspot")
	var r := await _http_post("/input/click", '{"test_id": "circle_hotspot"}')
	assert_int(r.code).is_equal(200)
	await _wait_physics(3)
	assert_int(_hits(fx, "CircleArea")["input_event"]).is_greater_equal(1)


func test_click_point_resolves_shape_geometry() -> void:
	var fx := _make_fixture()
	# ConvexPolygonShape2D centroid = shape origin (symmetric polygon).
	var r := await _http_post("/input/click", '{"path": "%s"}' % _base(fx, "PolyArea"))
	assert_int(r.code).is_equal(200)
	await _wait_physics(3)
	assert_int(_hits(fx, "PolyArea")["input_event"]).is_greater_equal(1)


func test_picking_disabled_returns_400() -> void:
	var fx := _make_fixture()
	# Standalone SubViewport defaults to physics_object_picking = false.
	var sub := SubViewport.new()
	sub.name = "SubNoPicking"
	sub.size = Vector2i(400, 300)
	var area := _make_hotspot("SubArea", Vector2(200, 150), RectangleShape2D.new())
	(area.get_node("Shape").shape as RectangleShape2D).size = Vector2(100, 60)
	sub.add_child(area)
	fx.add_child(sub)
	var r := await _http_post("/input/click", '{"path": "%s/SubNoPicking/SubArea"}' % String(fx.get_path()))
	assert_int(r.code).is_equal(400)
	assert_str(str(_error(r).get("code", ""))).is_equal("PICKING_DISABLED")


func test_plain_node2d_still_bad_target() -> void:
	var fx := _make_fixture()
	var plain := Node2D.new()
	plain.name = "PlainNode"
	fx.add_child(plain)
	var r := await _http_post("/input/click", '{"path": "%s/PlainNode"}' % String(fx.get_path()))
	assert_int(r.code).is_equal(400)
	assert_str(str(_error(r).get("code", ""))).is_equal("BAD_TARGET")


func test_missing_target_errors_unchanged() -> void:
	var r := await _http_post("/input/click", '{"path": "/root/DoesNotExist"}')
	assert_int(r.code).is_equal(404)
	assert_str(str(_error(r).get("code", ""))).is_equal("NODE_NOT_FOUND")
	var r2 := await _http_post("/input/click", "{}")
	assert_int(r2.code).is_equal(400)
	assert_str(str(_error(r2).get("code", ""))).is_equal("MISSING_PARAM")


func test_click_area2d_scene_file_and_assert_label() -> void:
	var scene := (load("res://scratch/spike/scenes/area2d_scene.tscn") as PackedScene).instantiate()
	_fixture = scene
	add_child(scene)
	var r := await _http_post("/input/click", '{"test_id": "e2e_hotspot"}')
	assert_int(r.code).is_equal(200)
	var data: Dictionary = _parsed(r).get("data", {})
	assert_bool(data.get("injected", false)).is_true()
	assert_str(str(data.get("mode", ""))).is_equal("picking")
	await _wait_physics(3)
	var label := scene.get_node("Lbl") as Label
	assert_str(label.text).is_equal("clicked")


func test_click_area2d_in_subviewport_container() -> void:
	var holder := Control.new()
	holder.name = "SubAreaHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var container := SubViewportContainer.new()
	container.name = "Container"
	container.position = Vector2(50, 50)
	container.size = Vector2(300, 200)
	container.stretch = true

	var sub := SubViewport.new()
	sub.name = "Sub"
	sub.size = Vector2i(300, 200)
	sub.physics_object_picking = true

	var area := _make_hotspot("SubArea", Vector2(150, 100), RectangleShape2D.new())
	(area.get_node("Shape").shape as RectangleShape2D).size = Vector2(80, 60)
	sub.add_child(area)
	container.add_child(sub)
	holder.add_child(container)
	_fixture = holder
	add_child(holder)
	await get_tree().process_frame

	var r := await _http_post("/input/click", '{"path": "%s"}' % _base(sub, "SubArea"))
	assert_int(r.code).is_equal(200)
	var data: Dictionary = _parsed(r).get("data", {})
	assert_bool(data.get("injected", false)).is_true()
	assert_str(str(data.get("mode", ""))).is_equal("picking")

	await _wait_physics(3)
	var hits := _hits(sub, "SubArea")
	assert_int(hits["input_event"]).is_greater_equal(1)
	assert_int(hits["mouse_entered"]).is_greater_equal(1)


func test_click_area2d_in_standalone_subviewport() -> void:
	var sub := SubViewport.new()
	sub.name = "StandaloneSub"
	sub.size = Vector2i(300, 200)
	sub.physics_object_picking = true

	var area := _make_hotspot("StandaloneArea", Vector2(150, 100), RectangleShape2D.new())
	(area.get_node("Shape").shape as RectangleShape2D).size = Vector2(80, 60)
	sub.add_child(area)
	_fixture = sub
	add_child(sub)
	await get_tree().process_frame

	var r := await _http_post("/input/click", '{"path": "%s"}' % _base(sub, "StandaloneArea"))
	assert_int(r.code).is_equal(200)
	var data: Dictionary = _parsed(r).get("data", {})
	assert_bool(data.get("injected", false)).is_true()
	assert_str(str(data.get("mode", ""))).is_equal("picking")

	await _wait_physics(3)
	var hits := _hits(sub, "StandaloneArea")
	assert_int(hits["input_event"]).is_greater_equal(1)
	assert_int(hits["mouse_entered"]).is_greater_equal(1)

