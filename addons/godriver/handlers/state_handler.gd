class_name TestDriverStateHandler
extends RefCounted
## GTD-015 — GET /state (SPEC §5.8): read-only view of the configured state
## autoload's script-declared properties.
##
## Static main-thread helpers called from TestDriverApi._main_* handlers.
## All methods return the funnel contract shape {"code": int, "body": Dictionary}.
## Writes (/state/set) and schema (/state/schema) are Phase 2/3 (GTD-032/033);
## §8 rules are frozen in SPEC.

## Project setting that names the state autoload (SPEC §5.8).
const STATE_AUTOLOAD_SETTING := "godriver/state_autoload"
const DEFAULT_STATE_AUTOLOAD := "GameState"


## Flat map of the state autoload's script-declared properties, serialized
## per §4 via TestDriverSerializer. Engine built-ins are excluded — only
## script variables (usage flag PROPERTY_USAGE_SCRIPT_VARIABLE) are listed.
## 409 STATE_AUTOLOAD_MISSING when the configured autoload is not in the tree.
static func read_state(tree: SceneTree) -> Dictionary:
	var autoload_name := str(ProjectSettings.get_setting(STATE_AUTOLOAD_SETTING, DEFAULT_STATE_AUTOLOAD))
	var state: Node = tree.root.get_node_or_null(NodePath("/root/" + autoload_name))
	if state == null:
		return {
			"code": 409,
			"body": {"ok": false, "error": {"code": "STATE_AUTOLOAD_MISSING", "message": "state autoload '%s' is not in the tree" % autoload_name, "details": {"hint": "set project setting '%s' to your state autoload's name, or add an autoload named '%s'" % [STATE_AUTOLOAD_SETTING, autoload_name]}}},
		}
	var values := {}
	for p in state.get_property_list():
		var usage: int = p.get("usage", 0)
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var prop_name: String = p.get("name", "")
			values[prop_name] = TestDriverSerializer.encode(state.get(prop_name))
	return {
		"code": 200,
		"body": {"ok": true, "data": {"autoload": autoload_name, "values": values}},
	}
