## GTD-053 (SPEC §5.10) — Window resize + state endpoints.
##
## POST /window/resize {width, height, stretch_mode?, aspect?, scale?} —
## sets the root Window size and optionally overrides the content-scale
## (stretch) configuration at runtime. GET /window/state reports the
## effective values. Works headless: root.size is settable under --headless
## (the driver's startup fix relies on the same mechanism).
class_name TestDriverWindowHandler
extends RefCounted

const MODES := ["disabled", "canvas_items", "viewport"]
const ASPECTS := ["ignore", "keep", "keep_width", "keep_height", "expand"]

const MODE_MAP := {
	"disabled": Window.CONTENT_SCALE_MODE_DISABLED,
	"canvas_items": Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
	"viewport": Window.CONTENT_SCALE_MODE_VIEWPORT,
}

const ASPECT_MAP := {
	"ignore": Window.CONTENT_SCALE_ASPECT_IGNORE,
	"keep": Window.CONTENT_SCALE_ASPECT_KEEP,
	"keep_width": Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH,
	"keep_height": Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT,
	"expand": Window.CONTENT_SCALE_ASPECT_EXPAND,
}


## GET /window/state — effective size + stretch configuration.
static func state(tree: SceneTree) -> Dictionary:
	var root := tree.root
	return {
		"code": 200,
		"body": {
			"ok": true,
			"data": {
				"size": {"width": root.size.x, "height": root.size.y},
				"viewport_size": {"width": root.get_visible_rect().size.x, "height": root.get_visible_rect().size.y},
				"content_scale_size": {"width": root.content_scale_size.x, "height": root.content_scale_size.y},
				"stretch": _stretch_snapshot(root),
			},
		},
	}


## POST /window/resize — change root size + optional stretch overrides.
## args: width, height (required ints > 0); stretch_mode, aspect (optional
## strings); scale (optional float > 0).
static func resize(tree: SceneTree, args: Dictionary) -> Dictionary:
	var width_v: Variant = args.get("width")
	var height_v: Variant = args.get("height")
	if width_v == null or height_v == null:
		return _type_mismatch("width and height are required", "positive integers")
	var width := _as_positive_int(width_v)
	var height := _as_positive_int(height_v)
	if width <= 0 or height <= 0:
		return _type_mismatch("width and height must be positive integers", "positive integers")

	var root := tree.root

	var mode_name := ""
	if args.get("stretch_mode", null) != null:
		mode_name = str(args["stretch_mode"])
		if not MODE_MAP.has(mode_name):
			return _type_mismatch("invalid stretch_mode", ", ".join(MODES))
	var aspect_name := ""
	if args.get("aspect", null) != null:
		aspect_name = str(args["aspect"])
		if not ASPECT_MAP.has(aspect_name):
			return _type_mismatch("invalid aspect", ", ".join(ASPECTS))
	var scale_v: Variant = args.get("scale", null)
	if scale_v != null:
		var scale_f := float(scale_v)
		if scale_f <= 0.0:
			return _type_mismatch("scale must be > 0", "positive float")

	# Apply stretch overrides first so the size change settles under the
	# final configuration.
	if mode_name != "":
		root.content_scale_mode = MODE_MAP[mode_name]
	if aspect_name != "":
		root.content_scale_aspect = ASPECT_MAP[aspect_name]
	if scale_v != null:
		root.content_scale_factor = float(scale_v)
	root.size = Vector2i(width, height)

	# Synchronous: Window.size setter updates the viewport immediately, so
	# get_visible_rect() already reflects the new size (keeps the handler
	# funnel-compatible — _main_* handlers must not await).

	return {
		"code": 200,
		"body": {
			"ok": true,
			"data": {
				"width": root.size.x,
				"height": root.size.y,
				"viewport_size": {"width": root.get_visible_rect().size.x, "height": root.get_visible_rect().size.y},
				"stretch": _stretch_snapshot(root),
			},
		},
	}


static func _stretch_snapshot(root: Window) -> Dictionary:
	return {
		"mode": MODES[root.content_scale_mode],
		"aspect": ASPECTS[root.content_scale_aspect],
		"scale": root.content_scale_factor,
	}


static func _as_positive_int(v: Variant) -> int:
	if v is int:
		return v
	if v is float and is_equal_approx(float(v), roundf(float(v))):
		return int(roundf(float(v)))
	return -1


static func _type_mismatch(message: String, expected: String) -> Dictionary:
	return {
		"code": 400,
		"body": {"ok": false, "error": {"code": "TYPE_MISMATCH", "message": message, "details": {"expected": expected}}},
	}

