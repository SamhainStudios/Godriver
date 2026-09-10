extends Node2D
## GTD-016 504 fixture — a scene whose _ready() never returns.
##
## _ready() suspends on a signal nothing emits, so is_node_ready() stays
## false forever → /reset must answer 504 SCENE_READY_TIMEOUT (SPEC §5.0).
## The suspended coroutine never resumes (the signal never fires), so the
## scene can be freed later without a delayed "previously freed" error.
signal never_fires


func _ready() -> void:
	await never_fires
