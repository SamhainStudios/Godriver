# Godriver Troubleshooting Guide

Common issues encountered when integrating Godriver with Godot projects, and how to resolve them.

---

## 1. Input & Clicking Issues

### "POST /input/click returns 200 OK, but my button or Area2D doesn't react"
- **Reason 1: 200 = Injected, not processed.** Godriver injects input events into the viewport's input pipeline. Signal handlers execute on subsequent frames. Always wait at least 1 frame or use client assertions (`assertVisible`, `waitSignal`, `assertProperty`) which auto-poll.
- **Reason 2: Area2D Physics Picking under `--headless`.** Godot's physics picking pipeline (`_process_picking()`) only flushes on physics frames. In headless mode without moving physics bodies, physics frames may not tick.
  - *Fix in Godriver*: Godriver automatically calls `_input_event()` directly on `CollisionObject2D` targets as a fallback to guarantee signal delivery in headless mode.
  - *Game Pattern*: You can also add `_unhandled_input(event)` bounds-checking in your hotspot scripts for instant response.
- **Reason 3: Viewport Object Picking Disabled.** If using `SubViewport`, ensure `physics_object_picking = true` is enabled on the SubViewport.
- **Reason 4: GUI Control Obscuring the Hotspot.** If a `Control` (e.g. transparent panel or margin container) is positioned over your `Area2D`, GUI input takes priority and consumes the event before physics picking sees it. Set `mouse_filter = MOUSE_FILTER_IGNORE` on background containers.

---

## 2. Scene Transitions & Lifecycle

### "Driver crashed when clicking a button that changes scene"
- **Symptoms**: `Invalid call. Nonexistent function 'get_path' in base 'Nil'`.
- **Reason**: When a button's `pressed` signal calls `change_scene_to_file()`, Godot frees the scene and button synchronously.
- **Fix**: Fixed in Godriver — viewport paths and response metadata are now captured *before* input injection occurs. Update to the latest addon.

### "Scene is loaded, but assertions fail on elements during transition animations"
- **Reason**: `loadScene()` returns when `is_node_ready()` is true, but transition tweens (e.g. 0.2s screen dissolves) may still be playing.
- **Fix**: Use `driver.loadScene(path, { tweenMode: "await" })` or follow up with `await driver.waitTween({ timeout: 3000 })`.

### "Tests pass individually, but leak state between scenarios"
- **Reason**: Godot Autoload singletons persist across scene reloads. By default, `/reset` only restores the primary `GameState` autoload.
- **Fix**: Configure all state-carrying autoloads in `project.godot`:
  ```ini
  [godriver]
  reset_autoloads=["TimeState", "InventoryManager", "PuzzleGraph"]
  ```
  Autoloads omitted from this list (like `AudioManager` or `SettingsManager`) will preserve their runtime values.

---

## 3. State & Type Coercion

### "Dictionary keys became strings when calling setState"
- **Symptoms**: Game code looks for `inventories[0]`, but the dictionary contains `{"0": [...]}`.
- **Reason**: JSON specifications require all object keys to be strings.
- **Fix**: Godriver's `_coerce_value` automatically converts dictionary string keys to integer keys if the target dictionary uses integer keys or all incoming keys are integer strings (including nested dictionaries).

### "Unknown key error on setState"
- **Symptoms**: `400 UNKNOWN_KEY: property 'xyz' does not exist on target`.
- **Reason**: `setState` only mutates script-declared variables (`PROPERTY_USAGE_SCRIPT_VARIABLE`). Built-in engine properties or undeclared dynamic variables are rejected to prevent typos.

---

## 4. Connectivity & Setup

### "Connection Refused at 127.0.0.1:9090"
- **Check 1**: Was Godot launched with `--test-driver`? Godriver stays completely dormant unless this CLI flag is present.
- **Check 2**: Is the addon enabled? Check **Project -> Project Settings -> Plugins -> Godriver Test Driver**.
- **Check 3**: Check port: If port 9090 is in use, start Godot with `--test-driver-port=9999` and pass `connect(9999)` in JS.

### "Godot imports .js files as resources and throws errors"
- **Fix**: Create an empty `.gdignore` file inside `js/` or `node_modules/`. This instructs Godot's resource filesystem scanner to skip the directory entirely.

### "Can't resolve @godriver/core in Node.js"
- **Fix**: Ensure your `package.json` contains `"type": "module"`. Godriver client libraries are ESM-only.
