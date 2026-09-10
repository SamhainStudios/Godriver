class_name TestDriverApi
extends Node
## GTD-011 — route handlers (SPEC §5.1 /health; auth per §1 token option).

const SPEC_VERSION := "0.1"

## When non-empty, requests must carry `Authorization: Bearer <token>`;
## otherwise 401 UNAUTHORIZED (SPEC Appendix A).
var token := ""


func _authorized(req: HttpRequest) -> bool:
	if token.is_empty():
		return true
	# godottpd stores headers verbatim (mixed case possible) — scan
	# case-insensitively.
	for key in req.headers:
		if String(key).to_lower() == "authorization":
			return String(req.headers[key]) == "Bearer " + token
	return false


func handle_health(req: HttpRequest, res: HttpResponse) -> bool:
	if not _authorized(req):
		res.json(401, {"ok": false, "error": {"code": "UNAUTHORIZED", "message": "missing or invalid bearer token"}})
		return true
	var v := Engine.get_version_info()
	var godot_version := "%d.%d.%d" % [v.major, v.minor, v.patch]
	res.json(200, {"ok": true, "data": {"status": "ok", "godot_version": godot_version, "spec_version": SPEC_VERSION}})
	return true
