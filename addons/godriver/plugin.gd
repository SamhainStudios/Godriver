@tool
extends EditorPlugin
## GTD-011 — EditorPlugin entry point.
##
## Enabling this plugin in Project Settings → Plugins registers the
## `Godriver` autoload (PLAN Open Q3). The autoload itself is dormant:
## it opens no socket and costs nothing per frame unless the game is launched
## with `--test-driver` (SPEC §1).

const AUTOLOAD_NAME := "Godriver"
# The leading `*` marks the autoload as enabled in project.godot.
const AUTOLOAD_PATH := "*res://addons/godriver/driver.gd"


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	print("[godriver] autoload '%s' registered — dormant until the game is launched with --test-driver" % AUTOLOAD_NAME)


func _exit_tree() -> void:
	# Godot 4 exposes no remove_autoload_singleton(); disabling the plugin does
	# not remove the autoload entry. Manual removal: Project Settings →
	# Autoload → delete the Godriver row. Documented in the README.
	pass
