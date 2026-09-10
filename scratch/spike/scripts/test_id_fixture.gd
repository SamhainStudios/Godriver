extends Node
## GTD-006 fixture — builds the test_id tree in code (no .tscn needed):
## Tagged (unique), DupA/DupB (duplicate pair), Untagged (no meta).

func _ready() -> void:
	name = "TestIdFixture"

	var tagged := Node.new()
	tagged.name = "Tagged"
	tagged.set_meta("test_id", "start_button")
	add_child(tagged)

	var dup_a := Node.new()
	dup_a.name = "DupA"
	dup_a.set_meta("test_id", "dup_id")
	add_child(dup_a)

	var dup_b := Node.new()
	dup_b.name = "DupB"
	dup_b.set_meta("test_id", "dup_id")
	add_child(dup_b)

	var untagged := Node.new()
	untagged.name = "Untagged"
	add_child(untagged)
