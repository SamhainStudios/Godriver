# Godriver HTTP API Reference

Complete reference for all HTTP endpoints exposed by the Godriver Godot addon (`addons/godriver`).

All requests and responses use JSON:
- Success envelope: `{"ok": true, "data": { ... }}`
- Error envelope: `{"ok": false, "error": {"code": "ERROR_CODE", "message": "...", "details": { ... }}}`
- Default Base URL: `http://127.0.0.1:9090`

---

## 1. Lifecycle

### `POST /reset`
Resets the game to a clean baseline for scenario isolation.
- Disconnects all signal watchers
- Resets determinism settings (`time_scale = 1.0`, `paused = false`)
- Resets primary state autoload (`godriver/state_autoload`, default `GameState`)
- Resets extra autoloads listed in project setting `godriver/reset_autoloads`
- Reloads the main scene (`application/run/main_scene`) and bounds readiness wait (5s)
- Kills or awaits active SceneTree tweens based on `tween_mode`
- Sweeps orphan nodes directly under `/root`
- Flushes buffered input events

**Request Body:**
```json
{
  "tween_mode": "kill" // "kill" (default) or "await"
}
```

**Response (200 OK):**
```json
{
  "ok": true,
  "data": {
    "reloaded_scene": "res://Main.tscn",
    "scene_ready": true,
    "missing_autoloads": [] // optional: listed if any extra autoloads were not found
  }
}
```

---

## 2. Scene Management

### `GET /scene/current`
Returns the currently loaded scene's file path and node path.

**Response (200 OK):**
```json
{
  "ok": true,
  "data": {
    "scene": "res://scenes/Level1.tscn",
    "node": "/root/Level1"
  }
}
```

### `POST /scene/load`
Changes scene to an arbitrary `.tscn` file and waits for `is_node_ready()`.

**Request Body:**
```json
{
  "path": "res://scenes/Level2.tscn",
  "tween_mode": "none" // "none" (default), "await", or "kill"
}
```

**Response (200 OK):**
```json
{
  "ok": true,
  "data": {
    "loaded": "res://scenes/Level2.tscn",
    "scene_ready": true
  }
}
```

---

## 3. Input Injection

### `POST /input/click`
Simulates a mouse hover, press, and release at the center of a `Control` or `CollisionObject2D` / `Area2D`.

**Request Body (by node path):**
```json
{ "path": "/root/Main/StartButton" }
```
**Request Body (by test_id):**
```json
{ "test_id": "start_button" }
```

**Response (200 OK):**
```json
{
  "ok": true,
  "data": {
    "injected": true,
    "target": "/root/Main/StartButton",
    "viewport": "/root",
    "mode": "gui" // "gui" for Control, "picking" for CollisionObject2D
  }
}
```

### `POST /input/type`
Focuses the target `Control` (e.g. `LineEdit`, `TextEdit`) and types unicode text.

**Request Body:**
```json
{
  "path": "/root/Main/NameInput",
  "text": "Player One"
}
```

**Response (200 OK):**
```json
{
  "ok": true,
  "data": {
    "injected": true,
    "chars": 10,
    "target": "/root/Main/NameInput"
  }
}
```

### `POST /input/key`
Injects an `InputMap` action (e.g. `"ui_accept"`) or key constant (e.g. `"KEY_ESCAPE"`).

**Request Body:**
```json
{
  "key": "ui_accept",
  "path": "/root/Main/Menu" // optional targeted focus
}
```

### `POST /input/key_down` / `POST /input/key_up` (GTD-054)
Split press and release so held key state is observable across frames. Same key resolution, targeting, and error codes as `/input/key`.

**Request Body:** same as `/input/key`.

**Response:** `{ "injected": true, "key": "move_right", "device": 16, "target": "", "pressed": true }`

A `key_down` without a matching `key_up` leaves the action held; `/reset` does NOT release held keys — pair the calls.

### `GET /input/map`
Returns all actions configured in the project's `InputMap` and their mapped events.

---

## 4. Assertions (Server-Side)

Assertions evaluate node state on the engine thread and return `passed: true | false` without failing the HTTP request.

### `POST /assert/visible`
Evaluates whether a `CanvasItem` or `Node3D` is visible in the tree.

**Request Body:**
```json
{
  "path": "/root/Main/HUD",
  "expected": true
}
```

**Response (200 OK):**
```json
{
  "ok": true,
  "data": {
    "target": "/root/Main/HUD",
    "actual": true,
    "expected": true,
    "passed": true
  }
}
```

### `POST /assert/enabled`
Evaluates whether a button or collision shape is enabled (`!disabled`).

**Request Body:**
```json
{
  "test_id": "submit_btn",
  "expected": true
}
```

### `POST /assert/property`
Evaluates any node property value against an expected value.

**Request Body:**
```json
{
  "path": "/root/Main/ScoreLabel",
  "property": "text",
  "expected": "Score: 100"
}
```

---

## 5. State Management

### `GET /state`
Reads script-declared properties from the state autoload or specified target object.

**Query Parameters:**
- `target`: (optional) Node path or `res://` script/resource path. Default: state autoload.

### `GET /state/schema`
Inspects property types and values on the target.

### `POST /state/set`
Mutates script variables on the target with automatic type coercion (integers, floats, colors, vectors, and dictionary integer keys).

**Request Body:**
```json
{
  "target": "res://autoload/inventory_manager.gd", // optional
  "values": {
    "gold": 500,
    "inventories": {
      "0": ["key", "map"] // Auto-coerced to {0: ["key", "map"]}
    }
  }
}
```

---

## 6. Signals

### `POST /signal/watch`
Connects an observer to a node signal. Emissions are buffered for polling/waiting.

**Request Body:**
```json
{
  "path": "/root/Main/Player",
  "signal": "level_up"
}
```

### `GET /signal/poll`
Reads and drains buffered signal emissions.

### `POST /signal/wait`
Long-polls until a signal fires, `/reset` occurs, or timeout expires.

**Request Body:**
```json
{
  "path": "/root/Main/Player",
  "signal": "level_up",
  "timeout": 5.0
}
```

---

## 7. Waits

### `GET /wait/frames?frames=N`
Blocks until `N` engine process frames have completed.

### `POST /wait/tween`
Blocks until all active SceneTree tweens complete.

**Request Body:**
```json
{
  "timeout": 5000 // milliseconds
}
```

---

## 8. Determinism

- `POST /dev/seed` — `{"seed": 12345}` — Seeds global RNG (`seed(N)`).
- `POST /dev/time_scale` — `{"scale": 2.0}` — Sets `Engine.time_scale`.
- `POST /dev/pause` — `{"enabled": true}` — Sets `SceneTree.paused`.
- `POST /dev/save/load` — `{"slot": "fixture1"}` — Copies `res://fixtures/fixture1.save` to `user://` if needed and verifies the file.

---

## 9. Server Health

### `GET /health`
Returns server status, engine version, and specification version.

**Response (200 OK):**
```json
{
  "ok": true,
  "data": {
    "status": "ok",
    "godot_version": "4.7.2",
    "spec_version": "0.1"
  }
}
```

---

## 10. Screenshots & Visuals (v0.3 / Phase 5)

> Requires active rendering context (fails under `--headless` with `400 HEADLESS_RENDERING_DISABLED`).

### `POST /screenshot/capture` (or `GET`)
Captures full viewport PNG.

**Request Body:**
```json
{
  "format": "binary", // "binary" (default) or "base64"
  "viewport": "/root/SubViewport" // optional
}
```

**Response (200 OK):**
- Binary PNG (`Content-Type: image/png`) by default.
- If `format="base64"`, JSON envelope: `{"ok": true, "data": {"image": "<base64>", "width": 1920, "height": 1080, "format": "png"}}`.

### `POST /screenshot/region` (or `GET`)
Captures a cropped PNG of a specific node's bounding rectangle or explicit rect.

**Request Body:**
```json
{
  "test_id": "main_menu", // or "path": "/root/Main/Menu"
  "rect": { "x": 0, "y": 0, "w": 300, "h": 200 }, // optional override
  "format": "binary"
}
```


### `POST /window/resize` (GTD-053)
Changes the root window size at runtime, optionally overriding stretch config.

**Request Body:**
```json
{
  "width": 1280,
  "height": 720,
  "stretch_mode": "canvas_items", // optional: disabled | canvas_items | viewport
  "aspect": "keep_width",         // optional: ignore | keep | keep_width | keep_height | expand
  "scale": 2.0                    // optional: content_scale_factor
}
```

**Response:** `{ "width": 1280, "height": 720, "viewport_size": {...}, "stretch": { "mode": "...", "aspect": "...", "scale": 1.0 } }`

Errors: `400 TYPE_MISMATCH` (bad width/height, invalid stretch strings with `details.expected`).

### `GET /window/state` (GTD-053)
Returns `{size, viewport_size, content_scale_size, stretch}` for the root window.
