# GTD-021 fixture — records Input action state each frame.
#
# The global /input/key path (Input.parse_input_event + flush_buffered_events)
# must update the engine's action state even under --headless (godot#73557
# workaround). Press+release are flushed in the SAME frame, so held state
# (is_action_pressed) is never observable — but is_action_just_pressed stays
# true for the remainder of that frame. The probe (added after the dispatcher
# autoload in tree order) samples in _process AFTER the drain and latches it.
extends Node

var saw_pressed := false


func _process(_delta: float) -> void:
	if not saw_pressed and Input.is_action_just_pressed("ui_accept"):
		saw_pressed = true
