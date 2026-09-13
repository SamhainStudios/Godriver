# Getting Started with Godriver

Godriver provides an HTTP-based test driver addon for Godot 4 and JS/BDD client libraries (`@godriver/core`, `@godriver/cucumber`, `@godriver/cli`).

---

## 1. Installation & Setup (3 Quick Steps)

### Step 1: Copy Addons to your Godot Project
Copy both required addon folders into your Godot project's `addons/` directory:
- `addons/godriver`
- `addons/godottpd` (the HTTP server backend)

In Godot, open **Project -> Project Settings -> Plugins** and enable **Godriver Test Driver**.

### Step 2: Prevent Godot from Scanning JS `node_modules`
Godot recursively scans project folders for `.js` and `.ts` files and attempts to import them as resources. To prevent import warnings, create an empty `.gdignore` file inside your JS directory or `node_modules/`:

```bash
# Touch .gdignore in node_modules or JS directory
touch node_modules/.gdignore
```

### Step 3: Configure ESM in your JS Package
Godriver client libraries are pure ES Modules (ESM). Ensure your `package.json` specifies `"type": "module"`:

```json
{
  "name": "my-game-tests",
  "type": "module",
  "dependencies": {
    "@godriver/core": "^0.1.0",
    "@godriver/cucumber": "^0.1.0",
    "@godriver/cli": "^0.1.0"
  }
}
```

If using Cucumber.js, create `cucumber.js` using ESM default export:

```javascript
// cucumber.js
export default {
  import: ["@godriver/cucumber/hooks", "@godriver/cucumber/steps"],
  format: ["progress"],
};
```

---

## 2. API Best Practices & Usage Guide

### Target Resolution (`test_id` & Node Paths)
You can target nodes by absolute node path or by `test_id` metadata. Using `test_id` decouples your tests from scene hierarchy changes.

#### Defining `test_id` in Godot:
1. **In the Godot Inspector**: Select any Node -> Scroll to the bottom -> **Metadata** -> Click **Add Metadata** -> Name: `test_id` (String) -> Value: `start_button`.
2. **In GDScript**:
   ```gdscript
   func _ready() -> void:
       set_meta("test_id", "start_button")
   ```

#### Using `test_id` in Tests:
```javascript
// 1. By test_id prefix convenience syntax (recommended)
await driver.click("test_id:start_btn");
await driver.assertVisible("test_id:score_label");
await driver.assertText("test_id:dialog_text", "Welcome!");

// 2. By testId option
await driver.click("start_btn", { testId: true });

// 3. By Node Path
await driver.click("/root/Main/StartButton");
```

### State Mutation (`setState`)
`setState(values, target)` sets property values. Note the parameter order:
1. `values` (Dictionary object of property values)
2. `target` (Optional target node path or script resource path)

```javascript
// Mutate autoload state
await driver.setState({ gold: 100, inventory: ["potion"] }, "res://autoload/inventory_manager.gd");

// Mutate node state directly
await driver.setState({ health: 50 }, "/root/Main/Player");
```

> **GDScript Tip for State Side-Effects**: Use GDScript property setters (`set(v)`) when state changes require UI or hotspot refreshes:
> ```gdscript
> var inventory: Array:
>     set(value):
>         inventory = value
>         _reapply_hotspots()
>         EventBus.state_changed.emit("inventory", value)
> ```
> `POST /state/set` calls `Object.set()`, which automatically triggers GDScript property setters!

### Key Input (`pressKey`)
`pressKey(key, opts)` accepts Godot `InputMap` action names or key names:

```javascript
// Action names configured in Input Map
await driver.pressKey("ui_accept");
await driver.pressKey("ui_cancel");

// Targeted key press on a specific Control
await driver.pressKey("ui_accept", { target: "/root/Main/LineEdit" });
```

### Loading Scenes (`loadScene`) & Waiting for Transitions
`loadScene(path, opts)` accepts `res://` paths or relative scene paths, and supports tween awaiting:

```javascript
await driver.loadScene("res://scenes/main_menu.tscn");
// Automatically normalizes relative paths to res://
await driver.loadScene("scenes/main_menu.tscn");

// Await scene transition tweens (e.g. 0.2s screen dissolves) before returning
await driver.loadScene("scenes/gameplay.tscn", { tweenMode: "await" });
```

### Scenario Reset (`driver.reset`) & Multi-Autoload Isolation
Reset the game to a clean baseline between test scenarios:

```javascript
// Full reset: kills tweens, reloads main scene, resets state autoloads
await driver.reset();

// Optional: await in-flight tweens before tearing down
await driver.reset({ tweenMode: "await" });
```

> **Multi-Autoload Reset**: By default, `/reset` restores your primary state autoload (`GameState`). If your game separates state across multiple autoloads (e.g. `TimeState`, `InventoryManager`, `PuzzleGraph`), list them in your `project.godot`:
> ```ini
> [godriver]
> reset_autoloads=["TimeState", "InventoryManager", "PuzzleGraph"]
> ```
> Autoloads not listed (e.g. `AudioManager`, `SettingsManager`) preserve their state across resets.

### Text Assertions (`assertText`)
Convenience method to assert text values on `Label`, `Button`, `RichTextLabel`, `LineEdit`:

```javascript
// Auto-retrying assertion with 3s timeout
await driver.assertText("test_id:score_label", "Score: 100");
await driver.assertText("/root/Main/Dialog/Text", "Hello, traveler!");
```

### Waiting for Tweens (`waitTween`)
Wait for any running tweens (e.g. animations, dissolves) to complete:

```javascript
await driver.click("test_id:fade_button");
await driver.waitTween({ timeout: 3000 }); // waits until active tweens drop to 0
```

### Headless `Area2D` & 2D Hotspot Guidance
In Godot 4, `Area2D` physics picking (`input_event` signal) relies on `Viewport._process_picking()`, which only flushes during physics process frames. In `--headless` mode when no physics bodies are actively moving, physics picking flushes can stall.

**Godriver's Built-In Fix**: When clicking a `CollisionObject2D` or `Area2D`, Godriver pushes the mouse press/release into the viewport and immediately triggers the object's `_input_event()` callback directly as a fallback. This guarantees delivery in headless mode without forcing game code changes!

**Recommended Game Pattern**: For point-and-click adventure games, having hotspots handle `_unhandled_input` checking collision shape bounds is still a robust pattern:

```gdscript
# hotspot.gd — Point-and-click adventure hotspot pattern
extends Area2D

signal clicked

@export var enabled: bool = true

func _ready() -> void:
    input_event.connect(_on_physics_input_event)

func _on_physics_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _trigger_click()

func _unhandled_input(event: InputEvent) -> void:
    if not enabled:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var local_pos = to_local(event.global_position)
        for child in get_children():
            if child is CollisionShape2D and child.shape:
                if child.shape.get_rect().has_point(local_pos):
                    get_viewport().set_input_as_handled()
                    _trigger_click()
                    break

func _trigger_click() -> void:
    clicked.emit()
```

---

## 3. Running Tests with `@godriver/cli`

Launch Godot automatically with the fail-fast watchdog and Cucumber runner:

```bash
npx godriver --godot /path/to/godot --project ./my_godot_project
```
