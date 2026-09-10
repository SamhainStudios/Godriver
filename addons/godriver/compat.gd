class_name TestDriverCompat
extends RefCounted
## GTD-022 — engine-version compatibility shims (SPEC §6 device constants).
##
## Godot 4.7 introduced InputEvent.DEVICE_ID_KEYBOARD (16) / DEVICE_ID_MOUSE
## (32) / DEVICE_ID_EMULATION (-1) (GH-116274). Injected events must carry
## these on 4.7+ or engine-side filtering can drop them; on 4.3–4.6 the
## convention was device=0. Detection is runtime (script constant lookup) so
## the addon floor stays at 4.3.

## True when the running engine exposes the 4.7 DEVICE_ID_* constants.
static var HAS_DEVICE_IDS: bool = "DEVICE_ID_KEYBOARD" in InputEvent


static func device_id_keyboard() -> int:
	return InputEvent.DEVICE_ID_KEYBOARD if HAS_DEVICE_IDS else 0


static func device_id_mouse() -> int:
	return InputEvent.DEVICE_ID_MOUSE if HAS_DEVICE_IDS else 0


static func device_id_emulation() -> int:
	return InputEvent.DEVICE_ID_EMULATION if HAS_DEVICE_IDS else 0


## Startup compatibility settings. Called once from driver.gd when the addon
## activates. Guarded so older engines (without the property) are unaffected.
static func apply_startup_settings() -> void:
	if "ignore_joypad_on_unfocused_application" in Input:
		# Synthetic joypad events must be processed in headless/unfocused CI
		# runs (PLAN Constraints, 4.7 input compat bullet).
		Input.ignore_joypad_on_unfocused_application = false
