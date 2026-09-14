class_name TestDriverCompat
extends RefCounted
## GTD-022 - engine-version compatibility shims (SPEC §6 device constants).
##
## Godot 4.7 introduced InputEvent.DEVICE_ID_KEYBOARD (16) / DEVICE_ID_MOUSE
## (32) / DEVICE_ID_EMULATION (-1) (GH-116274). Injected events must carry
## these on 4.7+ or engine-side filtering can drop them; on 4.3-4.6 the
## convention was device=0.
##
## IMPORTANT (4.4 verification finding): the 4.7-only members must NEVER be
## referenced directly - GDScript resolves member access at PARSE time, so
## even an unreachable branch fails to compile on 4.3-4.6. All lookups go
## through ClassDB / Object.set, which are runtime-safe on every version.

## True when the running engine exposes the 4.7 DEVICE_ID_* constants.
static var HAS_DEVICE_IDS: bool = ClassDB.class_has_integer_constant("InputEvent", "DEVICE_ID_KEYBOARD")


static func device_id_keyboard() -> int:
	if HAS_DEVICE_IDS:
		return int(ClassDB.class_get_integer_constant("InputEvent", "DEVICE_ID_KEYBOARD"))
	return 0


static func device_id_mouse() -> int:
	if HAS_DEVICE_IDS:
		return int(ClassDB.class_get_integer_constant("InputEvent", "DEVICE_ID_MOUSE"))
	return 0


static func device_id_emulation() -> int:
	if HAS_DEVICE_IDS:
		return int(ClassDB.class_get_integer_constant("InputEvent", "DEVICE_ID_EMULATION"))
	return 0


## Startup compatibility settings. Called once from driver.gd when the addon
## activates. Object.set() with a String property name is runtime-safe on
## older engines (no-op when the property does not exist).
static func apply_startup_settings() -> void:
	# Synthetic joypad events must be processed in headless/unfocused CI
	# runs (PLAN Constraints, 4.7 input compat bullet). The property exists
	# on 4.7+; set() is a silent no-op on older engines.
	Input.set("ignore_joypad_on_unfocused_application", false)
