extends GdUnitTestSuite
## GTD-011 — addon server unit tests: arg parsing, dormancy, /health shape,
## token auth, port-conflict detection.

const DriverScript := preload("res://addons/godriver/driver.gd")


func test_parse_args_defaults_and_overrides() -> void:
	var parsed: Dictionary = DriverScript.parse_args(PackedStringArray(["--test-driver"]))
	assert_int(parsed.port).is_equal(9090)
	assert_str(String(parsed.token)).is_equal("")
	parsed = DriverScript.parse_args(PackedStringArray([
		"--test-driver", "--test-driver-port=7777", "--test-driver-token=s3cret",
	]))
	assert_int(parsed.port).is_equal(7777)
	assert_str(String(parsed.token)).is_equal("s3cret")


func test_dormant_without_flag() -> void:
	# A driver node added to the tree without --test-driver must stay dormant:
	# no TestDriverServer child, no socket.
	var driver: Node = auto_free(DriverScript.new())
	scene_runner(driver).simulate_start()
	assert_int(driver.get_child_count()).is_equal(0)


func _get_health(port: int, token: String) -> Dictionary:
	# HTTPRequest capture via connected lambda into a Dictionary (the known
	# gotcha: awaiting an already-emitted request_completed deadlocks).
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var result := {}
	http.request_completed.connect(func(_r, code, _headers, body):
		result.code = code
		result.body = body.get_string_from_utf8())
	var headers := PackedStringArray()
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	http.request("http://127.0.0.1:%d/health" % port, headers)
	var waited := 0
	while not result.has("code") and waited < 300:
		await get_tree().process_frame
		waited += 1
	http.queue_free()
	return result


func test_health_shape() -> void:
	var server: TestDriverServer = auto_free(TestDriverServer.new())
	add_child(server)
	server.setup(0, "")
	assert_bool(server.start()).is_true()
	assert_int(server.bound_port).is_greater(0)
	var r: Dictionary = await _get_health(server.bound_port, "")
	assert_int(r.get("code", 0)).is_equal(200)
	var body: Dictionary = JSON.parse_string(r.body)
	assert_bool(body.ok).is_true()
	assert_str(body.data.status).is_equal("ok")
	assert_str(body.data.spec_version).is_equal("0.1")
	var v: Dictionary = Engine.get_version_info()
	assert_str(body.data.godot_version).is_equal("%d.%d.%d" % [v.major, v.minor, v.patch])
	server.stop()


func test_token_rejection() -> void:
	var server: TestDriverServer = auto_free(TestDriverServer.new())
	add_child(server)
	server.setup(0, "s3cret")
	assert_bool(server.start()).is_true()
	# No token → 401.
	var r: Dictionary = await _get_health(server.bound_port, "")
	assert_int(r.get("code", 0)).is_equal(401)
	var body: Dictionary = JSON.parse_string(r.body)
	assert_str(body.error.code).is_equal("UNAUTHORIZED")
	# Wrong token → 401.
	r = await _get_health(server.bound_port, "wrong")
	assert_int(r.get("code", 0)).is_equal(401)
	# Right token → 200.
	r = await _get_health(server.bound_port, "s3cret")
	assert_int(r.get("code", 0)).is_equal(200)
	server.stop()


func test_port_conflict() -> void:
	var first: TestDriverServer = auto_free(TestDriverServer.new())
	add_child(first)
	first.setup(19091, "")
	assert_bool(first.start()).is_true()
	var second: TestDriverServer = auto_free(TestDriverServer.new())
	add_child(second)
	second.setup(19091, "")
	assert_bool(second.start()).is_false()
	first.stop()
