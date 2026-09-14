class_name TestDriverNodeHandler
extends RefCounted
## GTD-013 — node read endpoints (SPEC §5.2).
##
## Static main-thread helpers called from TestDriverApi._main_* handlers.
## All methods return the funnel contract shape {"code": int, "body": Dictionary}.
## The serializer (TestDriverSerializer) is the single §4 implementation —
## values are never inline-serialized here.

const META_KEY := "test_id"


## Resolve a raw path string (from the URL) to a Node, applying the SPEC §5.2
## conventions: URL-decoded segments, leading "/root" optional.
## Returns {ok: true, node: Node} or {ok: false, code: int, error_code: String,
## message: String} with code 400 BAD_PATH or 404 NODE_NOT_FOUND.
static func resolve(root: Node, raw: String) -> Dictionary:
	var path := _url_decode(raw).strip_edges()
	if path.is_empty():
		return _bad_path("empty node path")
	# Normalize: optional leading slash, optional leading "root".
	if path.begins_with("/"):
		path = path.substr(1)
	if not path.begins_with("root"):
		path = "root/" + path
	# Absolute NodePath: relative paths would resolve from `root` itself
	# (looking for a child named "root"), which never exists.
	var node := root.get_node_or_null(NodePath("/" + path))
	if node == null:
		return {
			"ok": false, "code": 404,
			"error": {"code": "NODE_NOT_FOUND", "message": "no node at path /%s" % path},
		}
	return {"ok": true, "node": node}


## Node summary per SPEC §5.2 shared shape.
static func summary(node: Node) -> Dictionary:
	var script: Variant = node.get_script()
	var children: Array = []
	for child in node.get_children():
		children.append(child.name)
	var test_id: Variant = null
	if node.has_meta(META_KEY):
		test_id = str(node.get_meta(META_KEY))
	return {
		"path": String(node.get_path()),
		"name": String(node.name),
		"type": node.get_class(),
		"test_id": test_id,
		"child_count": node.get_child_count(),
		"children": children,
		"script": (script as Script).resource_path if script is Script else null,
	}


## GET /node/<path> — node summary.
static func get_info(root: Node, node_path: String) -> Dictionary:
	var r := resolve(root, node_path)
	if not r.ok:
		return {"code": r.code, "body": {"ok": false, "error": r.error}}
	return {"code": 200, "body": {"ok": true, "data": summary(r.node)}}


## GET /node/<path>/property/<name> — single property value per §4.
static func get_property(root: Node, node_path: String, prop: String) -> Dictionary:
	var r := resolve(root, node_path)
	if r.ok == false:
		return {"code": r.code, "body": {"ok": false, "error": r.error}}
	var node: Node = r.node
	prop = _url_decode(prop)
	# get() returns null both for "missing" and "present with null value" —
	# distinguish via the property list (also covers engine-private props,
	# SPEC §5.2).
	var listed := false
	for p in node.get_property_list():
		if p.get("name", "") == prop:
			listed = true
			break
	if not listed:
		return {
			"code": 404,
			"body": {"ok": false, "error": {"code": "PROPERTY_NOT_FOUND", "message": "node %s has no property '%s'" % [String(node.get_path()), prop]}},
		}
	var value: Variant = node.get(prop)
	match typeof(value):
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_OBJECT:
			# SPEC §4: Object/Callable/Signal unsupported in v0.1.
			return {
				"code": 400,
				"body": {"ok": false, "error": {"code": "UNSUPPORTED_TYPE", "message": "property '%s' holds an unsupported type (%s)" % [prop, type_string(typeof(value))]}},
			}
		_:
			pass
	var type_name := "null" if typeof(value) == TYPE_NIL else type_string(typeof(value))
	return {
		"code": 200,
		"body": {"ok": true, "data": {"name": prop, "type": type_name, "value": TestDriverSerializer.encode(value)}},
	}


## GET /node?test_id=<id> — §7 resolution: whole-tree scan, error-on-ambiguity.
## 200 {test_id, path} | 404 TEST_ID_NOT_FOUND | 409 AMBIGUOUS_TEST_ID.
## O(nodes) DFS; runs on the main thread via the dispatcher (GTD-012).
static func find_by_test_id(root: Node, test_id: String) -> Dictionary:
	var matches: Array[String] = []
	_scan_test_id(root, test_id, matches)
	if matches.is_empty():
		return {
			"code": 404,
			"body": {"ok": false, "error": {"code": "TEST_ID_NOT_FOUND", "message": "no node carries test_id '%s'" % test_id}},
		}
	if matches.size() > 1:
		return {
			"code": 409,
			"body": {"ok": false, "error": {"code": "AMBIGUOUS_TEST_ID", "message": "test_id '%s' matches %d nodes" % [test_id, matches.size()], "details": {"matches": matches}}},
		}
	return {"code": 200, "body": {"ok": true, "data": {"test_id": test_id, "path": matches[0]}}}


static func _scan_test_id(node: Node, test_id: String, matches: Array[String]) -> void:
	if node.has_meta(META_KEY) and str(node.get_meta(META_KEY)) == test_id:
		matches.append(String(node.get_path()))
	for child in node.get_children():
		_scan_test_id(child, test_id, matches)


## GET /nodes?group=<name> — paginated group listing (SPEC §5.2).
## Empty group → 200 with zero nodes (collections are exempt from ambiguity).
## limit must be 1..1000 (400 TYPE_MISMATCH otherwise); offset >= 0.
static func list_group(root: Node, group: String, limit: int, offset: int) -> Dictionary:
	var nodes := root.get_tree().get_nodes_in_group(group)
	var total := nodes.size()
	var page: Array = []
	var start := maxi(offset, 0)
	var end := mini(start + limit, total)
	for i in range(start, end):
		page.append(summary(nodes[i]))
	return {
		"code": 200,
		"body": {"ok": true, "data": {"nodes": page, "meta": {"total": total, "limit": limit, "offset": start}}},
	}


static func _bad_path(message: String) -> Dictionary:
	return {
		"ok": false, "code": 400,
		"error": {"code": "BAD_PATH", "message": message},
	}


## Minimal percent-decoding for node path segments (godottpd does not decode).
static func _url_decode(s: String) -> String:
	if not s.contains("%"):
		return s
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "%" and i + 2 < s.length():
			var hex := s.substr(i + 1, 2)
			if hex.is_valid_hex_number():
				out += String.chr(hex.hex_to_int())
				i += 3
				continue
		out += s[i]
		i += 1
	return out

## POST /node/<path>/property/<name> (GTD-055) - write a node property.
## The JSON value is decoded per SPEC §4 shapes and coerced to the
## property's declared type from get_property_list(). Callable/Signal/
## Object targets are rejected (400 UNSUPPORTED_TYPE).
static func set_property(root: Node, node_path: String, prop: String, value: Variant) -> Dictionary:
	var r := resolve(root, node_path)
	if r.ok == false:
		return {"code": r.code, "body": {"ok": false, "error": r.error}}
	var node: Node = r.node
	prop = _url_decode(prop)
	# Find the declared type from the property list (covers engine-private
	# and script vars; also rejects unknown properties).
	var declared_type := -1
	for p in node.get_property_list():
		if p.get("name", "") == prop:
			declared_type = int(p.get("type", TYPE_NIL))
			break
	if declared_type == -1:
		return {
			"code": 404,
			"body": {"ok": false, "error": {"code": "PROPERTY_NOT_FOUND", "message": "node %s has no property '%s'" % [String(node.get_path()), prop]}},
		}
	if declared_type == TYPE_CALLABLE or declared_type == TYPE_SIGNAL or declared_type == TYPE_OBJECT:
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "UNSUPPORTED_TYPE", "message": "property '%s' holds an unsupported type (%s)" % [prop, type_string(declared_type)]}},
		}
	# SPEC §8: null writes are type-dependent. Allowed for untyped
	# (Variant) properties and containers; rejected for value types.
	if value == null and declared_type != TYPE_NIL and declared_type != TYPE_ARRAY and declared_type != TYPE_DICTIONARY:
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "NULL_NOT_ALLOWED", "message": "property '%s' is a value type (%s); null writes are rejected" % [prop, type_string(declared_type)]}},
		}
	var decoded: Variant = value if declared_type == TYPE_NIL else TestDriverSerializer.decode(value, declared_type)
	if decoded == null and value != null:
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "TYPE_MISMATCH", "message": "value does not match property '%s' type (%s)" % [prop, type_string(declared_type)]}},
		}
	node.set(prop, decoded)
	return {
		"code": 200,
		"body": {"ok": true, "data": {"set": true, "name": prop, "type": type_string(declared_type), "value": TestDriverSerializer.encode(node.get(prop))}},
	}


static func _property_listed(node: Node, prop: String) -> bool:
	for p in node.get_property_list():
		if p.get("name", "") == prop:
			return true
	return false
