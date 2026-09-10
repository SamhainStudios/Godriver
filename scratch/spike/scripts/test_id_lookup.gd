class_name SpikeTestIdLookup
extends RefCounted
## GTD-006 (Spike C) — test_id metadata resolution.
##
## Scan semantics per SPEC §7: depth-first over the whole tree (root's
## children, not just current_scene — the spike loads fixtures as siblings
## of the main scene), matching nodes whose `test_id` metadata equals the
## query. Error-on-ambiguity: the CALLER decides 404 vs 409 from the match
## count; this class only reports matches.

const META_KEY := "test_id"


## Returns all node paths (absolute, "/root/..." form) whose test_id
## metadata equals `test_id`. Empty array = no match.
static func find_all(root: Node, test_id: String) -> Array[String]:
	var matches: Array[String] = []
	_scan(root, test_id, matches)
	return matches


static func _scan(node: Node, test_id: String, matches: Array[String]) -> void:
	if node.has_meta(META_KEY) and str(node.get_meta(META_KEY)) == test_id:
		matches.append(str(node.get_path()))
	for child in node.get_children():
		_scan(child, test_id, matches)
