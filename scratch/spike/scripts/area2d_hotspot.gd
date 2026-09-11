extends Area2D
## GTD-030 e2e fixture: hotspot that records a click into its Label sibling.

@onready var label: Label = get_node("../Lbl")

func _ready() -> void:
	input_event.connect(_on_input_event)
	mouse_entered.connect(func(): label.text = "entered")

func _on_input_event(_vp: Node, event: InputEvent, _idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		label.text = "clicked"

