extends Control
## Fixture for GTD-005 SubViewportContainer case: inner button press updates
## the inner label. The SubViewport is 200x200 inside a 400x400 container
## (stretch=true → 2x scale), so a naive window-space click would MISS —
## only the get_final_transform().affine_inverse() mapping lands correctly.

func _ready() -> void:
	$Container/Sub/Inner/Button.pressed.connect(
			func() -> void: $Container/Sub/Inner/Label.text = "pressed")
