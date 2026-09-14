# GTD-022 — TestDriverCompat: device-ID constants + startup settings.
#
# On 4.7.2 the DEVICE_ID_* constants exist (keyboard 16, mouse 32, emulation
# -1, GH-116274); on 4.3–4.6 the fallback is 0. Detection is runtime, so this
# suite asserts the 4.7.2 values and the event-stamping contract.
extends GdUnitTestSuite


func test_device_constants_on_47() -> void:
	# Engine-conditional: 4.7+ exposes the DEVICE_ID_* constants (16/32/-1);
	# 4.3-4.6 fall back to 0 (the pre-4.7 convention).
	if TestDriverCompat.HAS_DEVICE_IDS:
		assert_int(TestDriverCompat.device_id_keyboard()).is_equal(16)
		assert_int(TestDriverCompat.device_id_mouse()).is_equal(32)
		assert_int(TestDriverCompat.device_id_emulation()).is_equal(-1)
	else:
		assert_int(TestDriverCompat.device_id_keyboard()).is_equal(0)
		assert_int(TestDriverCompat.device_id_mouse()).is_equal(0)
		assert_int(TestDriverCompat.device_id_emulation()).is_equal(0)


func test_startup_settings_applied() -> void:
	# Must not error on any engine version; on 4.7 the property exists and
	# must end up false (synthetic joypad events processed when unfocused).
	# NOTE: the property is read via the runtime-safe `in` operator +
	# Object.get() with a String name - a direct member reference is a PARSE
	# error on 4.3-4.6 (4.4 verification finding, same as the compat shim).
	TestDriverCompat.apply_startup_settings()
	if "ignore_joypad_on_unfocused_application" in Input:
		assert_bool(Input.get("ignore_joypad_on_unfocused_application")).is_false()


func test_injected_events_carry_compat_device_ids() -> void:
	# Mouse button events stamped via _make_mouse_button carry the compat
	# mouse device; key events via _make_key carry the keyboard device.
	var mb := TestDriverInputHandler._make_mouse_button(Vector2.ZERO, Vector2.ZERO, true)
	assert_int(mb.device).is_equal(TestDriverCompat.device_id_mouse())
	var resolved := {"keycode": KEY_ENTER, "physical_keycode": KEY_NONE, "unicode": 0, "device": TestDriverCompat.device_id_keyboard()}
	var ke := TestDriverInputHandler._make_key(resolved, true)
	assert_int(ke.device).is_equal(TestDriverCompat.device_id_keyboard())
