class_name Gtd015GameState
extends Node
## GTD-015 fixture — minimal state autoload with script-declared properties.
## Used by test_scene_state_inputmap.gd as a stand-in "GameState" autoload.

var score := 42
var player_name := "hero"
var hard_mode := false
var inventory: Array[String] = ["sword", "potion"]
