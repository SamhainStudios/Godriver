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
You can target nodes by path or by Inspector-assigned `test_id` metadata:

```javascript
// 1. By Node Path
await driver.click("/root/Main/StartButton");

// 2. By test_id option
await driver.click("start_btn", { testId: true });

// 3. By test_id prefix convenience syntax
await driver.click("test_id:start_btn");
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

### Loading Scenes (`loadScene`)
`loadScene(path)` accepts `res://` paths or relative scene paths:

```javascript
await driver.loadScene("res://scenes/main_menu.tscn");
// Automatically normalizes relative paths to res://
await driver.loadScene("scenes/main_menu.tscn");
```

---

## 3. Running Tests with `@godriver/cli`

Launch Godot automatically with the fail-fast watchdog and Cucumber runner:

```bash
npx godriver --godot /path/to/godot --project ./my_godot_project
```
