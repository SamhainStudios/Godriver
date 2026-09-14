class_name TestDriverScreenshotHandler
extends RefCounted
## GTD-050 — POST/GET /screenshot/capture and /screenshot/region (SPEC §5.10).
##
## Screenshot capture and subregion cropping.
## - Captures full Viewport or specific Control/Node2D bounding region as PNG.
## - Running under `--headless` (DisplayServerHeadless / RendererDummy) returns
##   400 HEADLESS_RENDERING_DISABLED.
## - Requesting HDR output returns 400 HDR_NOT_SUPPORTED.
## - Supports raw PNG binary response (Content-Type: image/png) or base64 JSON
##   envelope when `format=base64`.
##
## Static main-thread helpers; funnel contract shape {"code", "body"|"raw"}.

const TestDriverInputHandler := preload("res://addons/godriver/handlers/input_handler.gd")


## Formats an Image into raw binary PNG or JSON base64 result dictionary.
static func _format_image_result(img: Image, args: Dictionary) -> Dictionary:
	var png_bytes := img.save_png_to_buffer()
	var format_str := str(args.get("format", "binary")).to_lower()
	if format_str == "base64":
		return {
			"code": 200,
			"body": {
				"ok": true,
				"data": {
					"image": Marshalls.raw_to_base64(png_bytes),
					"width": img.get_width(),
					"height": img.get_height(),
					"format": "png",
				}
			}
		}
	return {
		"code": 200,
		"raw": png_bytes,
		"content_type": "image/png",
		"headers": {
			"X-Image-Width": str(img.get_width()),
			"X-Image-Height": str(img.get_height()),
		}
	}


## Validates common prerequisites (headless mode, HDR restrictions).
static func _validate_rendering_context(args: Dictionary) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "HEADLESS_RENDERING_DISABLED",
					"message": "cannot capture screenshot in headless mode without an active rendering context",
				}
			}
		}

	var hdr_val: Variant = args.get("hdr", false)
	var is_hdr: bool = false
	if hdr_val is bool and hdr_val:
		is_hdr = true
	elif hdr_val is String and (hdr_val as String).to_lower() in ["true", "1"]:
		is_hdr = true

	var format_val := str(args.get("format", "")).to_lower()
	if is_hdr or format_val in ["hdr", "exr"]:
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "HDR_NOT_SUPPORTED",
					"message": "HDR screenshot capture is not supported; visual regression is SDR-only",
				}
			}
		}

	return {}


## POST/GET /screenshot/capture — captures full viewport as PNG.
static func capture(tree: SceneTree, args: Dictionary) -> Dictionary:
	var err := _validate_rendering_context(args)
	if not err.is_empty():
		return err

	var viewport: Viewport = null
	if args.has("viewport") and not str(args["viewport"]).is_empty():
		var vp_node := tree.root.get_node_or_null(NodePath(str(args["viewport"])))
		if vp_node is Viewport:
			viewport = vp_node
		else:
			return {
				"code": 404,
				"body": {
					"ok": false,
					"error": {
						"code": "VIEWPORT_NOT_FOUND",
						"message": "viewport node '%s' not found" % str(args["viewport"]),
					}
				}
			}
	else:
		viewport = tree.root.get_viewport()

	var tex := viewport.get_texture()
	if tex == null:
		return {
			"code": 500,
			"body": {
				"ok": false,
				"error": {
					"code": "TEXTURE_UNAVAILABLE",
					"message": "viewport texture is null",
				}
			}
		}

	var img := tex.get_image()
	if img == null or img.is_empty():
		return {
			"code": 500,
			"body": {
				"ok": false,
				"error": {
					"code": "IMAGE_EMPTY",
					"message": "failed to retrieve image from viewport texture",
				}
			}
		}

	return _format_image_result(img, args)


## POST/GET /screenshot/region — captures node bounds or explicit rect crop as PNG.
static func region(tree: SceneTree, args: Dictionary) -> Dictionary:
	var err := _validate_rendering_context(args)
	if not err.is_empty():
		return err

	var root := tree.root
	var node: Node = null
	var rect_i := Rect2i()
	var has_explicit_rect := false

	# Explicit rectangle dictionary check
	if args.has("rect") and args["rect"] is Dictionary:
		var r_dict: Dictionary = args["rect"]
		if r_dict.has("w") and r_dict.has("h"):
			var rx := int(r_dict.get("x", 0))
			var ry := int(r_dict.get("y", 0))
			var rw := int(r_dict.get("w", 0))
			var rh := int(r_dict.get("h", 0))
			if rw <= 0 or rh <= 0:
				return {
					"code": 400,
					"body": {
						"ok": false,
						"error": {
							"code": "INVALID_RECT",
							"message": "rect width and height must be greater than 0",
						}
					}
				}
			rect_i = Rect2i(rx, ry, rw, rh)
			has_explicit_rect = true

	# Target resolution by path or test_id
	if args.has("path") or args.has("test_id"):
		var t := TestDriverInputHandler.resolve_target(root, args)
		if not t.ok:
			return {"code": t.code, "body": {"ok": false, "error": t.error}}
		node = t.node
		if not (node is CanvasItem):
			return {
				"code": 400,
				"body": {
					"ok": false,
					"error": {
						"code": "BAD_TARGET",
						"message": "node '%s' is not a CanvasItem or Control" % t.path,
					}
				}
			}
		if not has_explicit_rect:
			if node is Control:
				var gr := (node as Control).get_global_rect()
				rect_i = Rect2i(int(gr.position.x), int(gr.position.y), int(gr.size.x), int(gr.size.y))
			elif node is Node2D:
				var pos := (node as Node2D).global_position
				rect_i = Rect2i(int(pos.x), int(pos.y), 32, 32)
	elif not has_explicit_rect:
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "MISSING_PARAM",
					"message": "requires target 'path', 'test_id', or explicit 'rect' parameter",
				}
			}
		}

	var viewport: Viewport = null
	if node != null:
		viewport = node.get_viewport()
	elif args.has("viewport") and not str(args["viewport"]).is_empty():
		var vp_node := root.get_node_or_null(NodePath(str(args["viewport"])))
		if vp_node is Viewport:
			viewport = vp_node
	if viewport == null:
		viewport = root.get_viewport()

	var tex := viewport.get_texture()
	if tex == null:
		return {
			"code": 500,
			"body": {
				"ok": false,
				"error": {
					"code": "TEXTURE_UNAVAILABLE",
					"message": "viewport texture is null",
				}
			}
		}

	var img := tex.get_image()
	if img == null or img.is_empty():
		return {
			"code": 500,
			"body": {
				"ok": false,
				"error": {
					"code": "IMAGE_EMPTY",
					"message": "failed to retrieve image from viewport texture",
				}
			}
		}

	var img_bounds := Rect2i(0, 0, img.get_width(), img.get_height())
	var crop_rect := rect_i.intersection(img_bounds)
	if crop_rect.size.x <= 0 or crop_rect.size.y <= 0:
		return {
			"code": 400,
			"body": {
				"ok": false,
				"error": {
					"code": "OUT_OF_BOUNDS",
					"message": "region rectangle falls outside viewport bounds (%dx%d)" % [img.get_width(), img.get_height()],
				}
			}
		}

	var cropped := img.get_region(crop_rect)
	return _format_image_result(cropped, args)
