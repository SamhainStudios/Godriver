extends Node
## Fixture scene for the spikes: button press updates the label (GTD-005 uses this).

func _ready() -> void:
	$Button.pressed.connect(func() -> void: $Label.text = "pressed")
