/**
 * GTD-056 tests: tree walk + Screen Objects renderer with a mocked driver.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { generateScreens, renderScreensModule } from "../src/codegen.js";

/** Build a mock driver from a nested node map. @param {Record<string, {type: string, test_id?: string|null, children?: string[]}>} nodes @returns {{ request: (path: string) => Promise<Record<string, unknown>> }} */
function mockDriver(nodes) {
	return {
		request: async (path) => {
			const clean = path.replace(/^\/node/, "").replace(/^\//, "");
			const node = nodes[clean];
			if (!node) {
				throw new Error(`404 ${path}`);
			}
			return {
				path: `/${clean}`,
				name: clean.split("/").pop(),
				type: node.type,
				test_id: node.test_id ?? null,
				children: node.children ?? [],
			};
		},
	};
}

const DEMO_NODES = {
	root: { type: "Window", children: ["Main"] },
	"root/Main": { type: "Node2D", children: ["Player", "HUD"] },
	"root/Main/Player": { type: "CharacterBody2D" },
	"root/Main/HUD": { type: "CanvasLayer", children: ["ScoreLabel", "PauseMenu"] },
	"root/Main/HUD/ScoreLabel": { type: "Label", test_id: "score_label" },
	"root/Main/HUD/PauseMenu": { type: "ColorRect", test_id: "pause_menu", children: ["PausedLabel"] },
	"root/Main/HUD/PauseMenu/PausedLabel": { type: "Label", test_id: "paused_label" },
};

test("generateScreens collects every test_id node with its path and type", async () => {
	const entries = await generateScreens(mockDriver(DEMO_NODES));
	const byId = Object.fromEntries(entries.map((e) => [e.testId, e]));
	assert.equal(entries.length, 3);
	assert.equal(byId.score_label.path, "/root/Main/HUD/ScoreLabel");
	assert.equal(byId.score_label.type, "Label");
	assert.equal(byId.paused_label.path, "/root/Main/HUD/PauseMenu/PausedLabel");
});

test("renderScreensModule emits a module with the test_id map and helpers", async () => {
	const entries = await generateScreens(mockDriver(DEMO_NODES));
	const src = renderScreensModule(entries, { godotVersion: "4.7.2" });
	assert.ok(src.includes('"score_label": "/root/Main/HUD/ScoreLabel"'));
	assert.ok(src.includes('"paused_label": "/root/Main/HUD/PauseMenu/PausedLabel"'));
	assert.ok(src.includes("class GameScreens"));
	assert.ok(src.includes("async click(name)"));
	assert.ok(src.includes("async setProperty(name, prop, value)"));
	assert.ok(src.includes("Godot 4.7.2"));
});

test("generated module is importable and helpers resolve paths", async () => {
	const entries = await generateScreens(mockDriver(DEMO_NODES));
	const src = renderScreensModule(entries);
	// The generated module imports @godriver/core (bare specifier, unresolvable
	// from a data: URL) - the test only exercises the map + class.
	const importable = src.replace('import { connect } from "@godriver/core";', "const connect = async () => ({});");
	const module = await import(`data:text/javascript;base64,${Buffer.from(importable).toString("base64")}`);
	assert.equal(module.TEST_IDS.score_label, "/root/Main/HUD/ScoreLabel");
	const calls = [];
	const fakeDriver = {
		click: async (target) => ({ target }),
		assertVisible: async (target) => ({ target }),
		request: async (p) => ({ value: p }),
	};
	const screens = new module.GameScreens(fakeDriver);
	assert.equal(screens.path("score_label"), "/root/Main/HUD/ScoreLabel");
	const clicked = await screens.click("score_label");
	assert.equal(clicked.target, "/root/Main/HUD/ScoreLabel");
	assert.throws(() => screens.path("nope"), /unknown test_id/);
});
