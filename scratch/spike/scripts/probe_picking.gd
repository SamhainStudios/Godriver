# GTD-030 debug probe: isolates physics-picking delivery from HTTP/driver.
# Run: Godot --headless --path . res://scratch/spike/scenes/probe_picking.tscn
extends Node

var hits := { "input_event": 0, "entered": 0 }

func _ready() -> void:
	var vp := get_tree().root
	print("PROBE root.size=", vp.size, " visible_rect=", vp.get_visible_rect().size,
			" picking=", vp.physics_object_picking, " mouse_mode=", Input.get_mouse_mode())

	var area := Area2D.new()
	area.name = "Hotspot"
	area.position = Vector2(300, 200)
	area.input_pickable = true
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 80)
	cs.shape = shape
	area.add_child(cs)
	area.input_event.connect(_on_input_event)
	area.mouse_entered.connect(_on_entered)
	add_child(area)
	await get_tree().process_frame

	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(300, 200)
	mm.global_position = Vector2(300, 200)
	vp.push_input(mm, true)
	await get_tree().process_frame
	print("PROBE after motion: hovered=", vp.gui_get_hovered_control())

	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(300, 200)
	mb.global_position = Vector2(300, 200)
	vp.push_input(mb, true)
	var mb2: InputEventMouseButton = mb.duplicate()
	mb2.pressed = false
	vp.push_input(mb2, true)

	for i in 6:
		await get_tree().physics_frame
		print("PROBE phys ", i, " hits=", hits)

	print("PROBE manual _process_picking call:")
	vp._process_picking()
	await get_tree().process_frame
	print("PROBE final hits=", hits)
	get_tree().quit(0 if hits.input_event > 0 else 1)

func _on_input_event(_vp: Viewport, ev: InputEvent, _shape: int) -> void:
	hits.input_event += 1
	print("PROBE INPUT_EVENT frame=", Engine.get_physics_frames(), " ev=", ev)

func _on_entered() -> void:
	hits.entered += 1
	print("PROBE MOUSE_ENTERED")
