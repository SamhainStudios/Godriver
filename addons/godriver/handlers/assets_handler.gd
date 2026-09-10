class_name TestDriverAssetsHandler
extends RefCounted
## GTD-024 — GET /assets/loaded (SPEC §5.9a).
##
## DECISION GATE (GTD-024): Godot 4.7 exposes NO public API to enumerate all
## loaded resources — ResourceLoader.list_handled_resources() does not exist
## (verified against the 4.7.2 ClassDB method table). The endpoint therefore
## reports the engine-wide resource COUNT (Performance monitor) plus the
## DRIVER-TRACKED inventory (scenes loaded through /scene/load and /reset).
## A full inventory is deferred until Godot ships an enumeration API.
##
## Static main-thread helpers; funnel contract shape {"code", "body"}.

## Driver-tracked loads: [{path: String, source: String}]. Static — persists
## for the process lifetime (the addon's own lifetime).
static var _tracked: Array[Dictionary] = []


## Record a scene load (called by scene_handler on successful transitions).
static func track(path: String, source: String) -> void:
	_tracked.append({"path": path, "source": source})


static func loaded(tree: SceneTree, limit: int, offset: int) -> Dictionary:
	if limit < 1 or limit > 1000:
		return {
			"code": 400,
			"body": {"ok": false, "error": {"code": "TYPE_MISMATCH", "message": "limit must be within 1..1000", "details": {"expected": "1..1000", "got": limit}}},
		}
	var total := _tracked.size()
	var offset_clamped := clampi(offset, 0, total)
	var page := _tracked.slice(offset_clamped, offset_clamped + limit)
	var count: int = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	return {
		"code": 200,
		"body": {"ok": true, "data": {
			"count": count,
			"resources": page,
			"meta": {"total": total},
		}},
	}
