extends GdUnitTestSuite
## GTD-014 — test_id resolution + group queries (SPEC §5.2/§7):
## /node?test_id=x (200/404/409), /nodes?group=y (pagination, meta.total).

var _server: TestDriverServer
var _fixture: Node


func before_test() -> void:
	# GdUnit reuses the suite node across tests — drop the previous fixture
	# or group membership accumulates (3 nodes × N runs).
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.queue_free()
		await get_tree().process_frame
	_server = auto_free(TestDriverServer.new())
	add_child(_server)
	_server.setup(0, "")
	assert_bool(_server.start()).is_true()
	# Fixture: Main > Unique(test_id=uid_1) + DupA(test_id=dup) + DupB(test_id=dup)
	#          + Grouped1/Grouped2/Grouped3 (group "gtd014_group") + Untagged.
	var main := Node.new()
	main.name = "Gtd014Main"
	var unique := Node.new()
	unique.name = "Unique"
	unique.set_meta("test_id", "uid_1")
	var dup_a := Node.new()
	dup_a.name = "DupA"
	dup_a.set_meta("test_id", "dup")
	var dup_b := Node.new()
	dup_b.name = "DupB"
	dup_b.set_meta("test_id", "dup")
	var untagged := Node.new()
	untagged.name = "Untagged"
	var grouped: Array[Node] = []
	for i in range(3):
		var g := Node.new()
		g.name = "Grouped%d" % (i + 1)
		g.add_to_group("gtd014_group")
		main.add_child(g)
		grouped.append(g)
	main.add_child(unique)
	main.add_child(dup_a)
	main.add_child(dup_b)
	main.add_child(untagged)
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


func _parsed(r: Dictionary) -> Dictionary:
	return JSON.parse_string(r.body)


func _error(r: Dictionary) -> Dictionary:
	return _parsed(r).get("error", {})


func test_testid_resolution_semantics() -> void:
	# Unique → 200 {test_id, path}.
	var r: Dictionary = await _http_get("/node?test_id=uid_1")
	assert_int(r.get("code", 0)).is_equal(200)
	var d: Dictionary = _parsed(r).get("data", {})
	assert_str(str(d.get("test_id"))).is_equal("uid_1")
	assert_str(str(d.get("path"))).is_equal(String(_fixture.get_path()) + "/Unique")
	# Unknown → 404 TEST_ID_NOT_FOUND.
	r = await _http_get("/node?test_id=nope")
	assert_int(r.get("code", 0)).is_equal(404)
	assert_str(str(_error(r).get("code"))).is_equal("TEST_ID_NOT_FOUND")
	# Duplicate → 409 AMBIGUOUS_TEST_ID with details.matches (2 paths).
	r = await _http_get("/node?test_id=dup")
	assert_int(r.get("code", 0)).is_equal(409)
	var err: Dictionary = _error(r)
	assert_str(str(err.get("code"))).is_equal("AMBIGUOUS_TEST_ID")
	var matches: Array = err.get("details", {}).get("matches", [])
	assert_int(matches.size()).is_equal(2)
	# Missing param → 400 MISSING_PARAM.
	r = await _http_get("/node")
	assert_int(r.get("code", 0)).is_equal(400)
	assert_str(str(_error(r).get("code"))).is_equal("MISSING_PARAM")


func test_numeric_test_id_stays_string() -> void:
	# godottpd auto-converts numeric query values — a test_id of "123" must
	# still resolve (str() coercion in _extract_args).
	var tagged := Node.new()
	tagged.name = "NumericTag"
	tagged.set_meta("test_id", "123")
	_fixture.add_child(tagged)
	var r: Dictionary = await _http_get("/node?test_id=123")
	assert_int(r.get("code", 0)).is_equal(200)
	assert_str(str(_parsed(r).get("data", {}).get("path"))).is_equal(String(tagged.get_path()))


func test_group_pagination_and_errors() -> void:
	# Full listing: 3 nodes, meta.total = 3.
	var r: Dictionary = await _http_get("/nodes?group=gtd014_group")
	assert_int(r.get("code", 0)).is_equal(200)
	var d: Dictionary = _parsed(r).get("data", {})
	var meta: Dictionary = d.get("meta", {})
	assert_int(int(meta.get("total", -1))).is_equal(3)
	assert_int(int(meta.get("limit", -1))).is_equal(100)
	assert_int(int(meta.get("offset", -1))).is_equal(0)
	var nodes: Array = d.get("nodes", [])
	assert_int(nodes.size()).is_equal(3)
	assert_str(str(nodes[0].get("name"))).is_equal("Grouped1")
	assert_str(str(nodes[0].get("type"))).is_equal("Node")
	# Pagination: limit=2 → 2 nodes, total still 3.
	r = await _http_get("/nodes?group=gtd014_group&limit=2")
	d = _parsed(r).get("data", {})
	assert_int((d.get("nodes", []) as Array).size()).is_equal(2)
	assert_int(int(d.get("meta", {}).get("total", -1))).is_equal(3)
	# offset=2 → last node only.
	r = await _http_get("/nodes?group=gtd014_group&limit=2&offset=2")
	d = _parsed(r).get("data", {})
	var page: Array = d.get("nodes", [])
	assert_int(page.size()).is_equal(1)
	assert_str(str(page[0].get("name"))).is_equal("Grouped3")
	# Empty group → 200 with zero nodes (NOT 404, SPEC §7).
	r = await _http_get("/nodes?group=no_such_group")
	assert_int(r.get("code", 0)).is_equal(200)
	assert_int(int(_parsed(r).get("data", {}).get("meta", {}).get("total", -1))).is_equal(0)
	# limit out of range → 400 TYPE_MISMATCH with details.expected.
	r = await _http_get("/nodes?group=gtd014_group&limit=1001")
	assert_int(r.get("code", 0)).is_equal(400)
	var err: Dictionary = _error(r)
	assert_str(str(err.get("code"))).is_equal("TYPE_MISMATCH")
	assert_str(str(err.get("details", {}).get("expected"))).is_equal("1..1000")
	# Missing group → 400 MISSING_PARAM.
	r = await _http_get("/nodes")
	assert_int(r.get("code", 0)).is_equal(400)
	assert_str(str(_error(r).get("code"))).is_equal("MISSING_PARAM")
