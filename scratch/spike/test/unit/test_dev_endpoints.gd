extends GdUnitTestSuite
## GTD-034 — Determinism endpoints (/dev/seed, /dev/time_scale, /dev/pause, /dev/save/load)

var _server: TestDriverServer


func before_test() -> void:
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()


func after_test() -> void:
	_server.stop()
	Engine.time_scale = 1.0
	get_tree().paused = false


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


func test_dev_seed_determinism() -> void:
	var res := await _http_post("/dev/seed", JSON.stringify({"seed": 12345}))
	assert_int(res.code).is_equal(200)
	var data: Dictionary = _parsed(res).get("data", {})
	assert_bool(data.get("seeded", false)).is_true()
	assert_int(int(data.get("seed", 0))).is_equal(12345)

	# Global randi() check
	var val1 := randi()
	seed(12345)
	var val2 := randi()
	assert_int(val1).is_equal(val2)


func test_dev_time_scale() -> void:
	var res := await _http_post("/dev/time_scale", JSON.stringify({"scale": 2.5}))
	assert_int(res.code).is_equal(200)
	var data: Dictionary = _parsed(res).get("data", {})
	assert_float(float(data.get("time_scale", 0.0))).is_equal(2.5)
	assert_float(Engine.time_scale).is_equal(2.5)

	# Reset time scale
	Engine.time_scale = 1.0


func test_dev_pause() -> void:
	var res1 := await _http_post("/dev/pause", JSON.stringify({"enabled": true}))
	assert_int(res1.code).is_equal(200)
	assert_bool(get_tree().paused).is_true()

	var res2 := await _http_post("/dev/pause", JSON.stringify({"enabled": false}))
	assert_int(res2.code).is_equal(200)
	assert_bool(get_tree().paused).is_false()


func test_dev_save_load() -> void:
	# Create a dummy save file in user://
	var user_file := FileAccess.open("user://test_fixture.save", FileAccess.WRITE)
	user_file.store_string("dummy save data")
	user_file.close()

	var res := await _http_post("/dev/save/load", JSON.stringify({"slot": "test_fixture"}))
	assert_int(res.code).is_equal(200)
	var data: Dictionary = _parsed(res).get("data", {})
	assert_str(data.get("slot", "")).is_equal("test_fixture")
	assert_bool(data.get("loaded", false)).is_true()


func test_dev_errors() -> void:
	# 400 MISSING_PARAM
	var res_missing := await _http_post("/dev/seed", "{}")
	assert_int(res_missing.code).is_equal(400)
	assert_str(_parsed(res_missing).get("error", {}).get("code", "")).is_equal("MISSING_PARAM")

	# 400 TYPE_MISMATCH
	var res_mismatch := await _http_post("/dev/time_scale", JSON.stringify({"scale": "invalid"}))
	assert_int(res_mismatch.code).is_equal(400)
	assert_str(_parsed(res_mismatch).get("error", {}).get("code", "")).is_equal("TYPE_MISMATCH")

	# 404 FILE_NOT_FOUND
	var res_not_found := await _http_post("/dev/save/load", JSON.stringify({"slot": "non_existent_slot_123"}))
	assert_int(res_not_found.code).is_equal(404)
	assert_str(_parsed(res_not_found).get("error", {}).get("code", "")).is_equal("FILE_NOT_FOUND")
