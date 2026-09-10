class_name PropsNode
extends Node
## GTD-013 test fixture — node with typed properties for §4 round-trip tests.

@export var v2 := Vector2(1, 2)
@export var col := Color(0.25, 0.5, 0.75, 1.0)
@export var np := NodePath("root/Main/Button")
@export var s := "hello"
@export var b := true
@export var i := 7
var fn: Callable = Callable()  # unsupported type (§4) for UNSUPPORTED_TYPE test
