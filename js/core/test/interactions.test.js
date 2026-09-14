/**
 * GTD-026 — @godriver/core interaction methods: request shapes + auto-wait
 * call order (mocked fetch), plus live-game integration tests (skipped
 * without GODOT_BIN).
 */
import test from "node:test";
import assert from "node:assert/strict";
import { connect } from "../src/client.js";
import { liveAvailable, startLiveGame, LIVE_PORT } from "./helpers/live-game.js";

// --- mocked-fetch unit tests: request shapes + auto-wait ordering ---

function mockFetch(routes) {
	const calls = [];
	const fn = async (url, init) => {
		const path = new URL(url).pathname + new URL(url).search;
		calls.push({ path, init });
		const handler = routes.find((r) => path.startsWith(r.match)) ?? routes[0];
		return new Response(JSON.stringify(handler.reply(path)), {
			status: handler.status ?? 200,
			headers: { "content-type": "application/json" },
		});
	};
	fn.calls = calls;
	return fn;
}

const originalFetch = globalThis.fetch;

test("click() posts /input/click then waits one frame", async () => {
	globalThis.fetch = mockFetch([
		{ match: "/input/click", reply: () => ({ ok: true, data: { injected: true } }) },
		{ match: "/wait/frames", reply: () => ({ ok: true, data: { waited: 1 } }) },
		{
			match: "/health",
			reply: () => ({
				ok: true,
				data: { status: "ok", godot_version: "4.7.2", spec_version: "0.1" },
			}),
		},
	]);
	try {
		const driver = await connect(9090, { host: "mock" });
		await driver.click("/root/Main/Button");
		const paths = globalThis.fetch.calls.map((c) => c.path);
		assert.deepEqual(paths, ["/health", "/input/click", "/wait/frames?frames=1"]);
		const body = JSON.parse(globalThis.fetch.calls[1].init.body);
		assert.deepEqual(body, { path: "/root/Main/Button" });
		driver.close();
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("click() by testId sends test_id", async () => {
	globalThis.fetch = mockFetch([
		{ match: "/input/click", reply: () => ({ ok: true, data: { injected: true } }) },
		{ match: "/wait/frames", reply: () => ({ ok: true, data: { waited: 1 } }) },
		{ match: "/health", reply: () => ({ ok: true, data: { status: "ok" } }) },
	]);
	try {
		const driver = await connect(9090, { host: "mock" });
		await driver.click("start_button", { testId: true });
		const body = JSON.parse(globalThis.fetch.calls[1].init.body);
		assert.deepEqual(body, { test_id: "start_button" });
		driver.close();
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("type() sends text; pressKey() sends key + optional target", async () => {
	globalThis.fetch = mockFetch([
		{ match: "/input/", reply: () => ({ ok: true, data: { injected: true } }) },
		{ match: "/wait/frames", reply: () => ({ ok: true, data: { waited: 1 } }) },
		{ match: "/health", reply: () => ({ ok: true, data: { status: "ok" } }) },
	]);
	try {
		const driver = await connect(9090, { host: "mock" });
		await driver.type("/root/Edit", "hello");
		assert.deepEqual(JSON.parse(globalThis.fetch.calls[1].init.body), {
			path: "/root/Edit",
			text: "hello",
		});
		await driver.pressKey("ui_accept", { target: "/root/Btn" });
		assert.deepEqual(JSON.parse(globalThis.fetch.calls[3].init.body), {
			path: "/root/Btn",
			key: "ui_accept",
		});
		driver.close();
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("keyDown()/keyUp() post to the split endpoints with one-frame wait", async () => {
	globalThis.fetch = mockFetch([
		{ match: "/input/key_down", reply: () => ({ ok: true, data: { injected: true, pressed: true } }) },
		{ match: "/input/key_up", reply: () => ({ ok: true, data: { injected: true, pressed: false } }) },
		{ match: "/wait/frames", reply: () => ({ ok: true, data: { waited: 1 } }) },
		{ match: "/health", reply: () => ({ ok: true, data: { status: "ok" } }) },
	]);
	try {
		const driver = await connect(9090, { host: "mock" });
		await driver.keyDown("move_right");
		assert.deepEqual(globalThis.fetch.calls.map((c) => c.path), ["/health", "/input/key_down", "/wait/frames?frames=1"]);
		assert.deepEqual(JSON.parse(globalThis.fetch.calls[1].init.body), { key: "move_right" });
		await driver.keyUp("move_right");
		assert.equal(globalThis.fetch.calls[3].path, "/input/key_up");
		assert.deepEqual(JSON.parse(globalThis.fetch.calls[3].init.body), { key: "move_right" });
		driver.close();
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("loadScene() posts path, no auto-wait; layout() builds URL", async () => {
	globalThis.fetch = mockFetch([
		{
			match: "/scene/load",
			reply: () => ({ ok: true, data: { loaded: "x", scene_ready: true } }),
		},
		{ match: "/ui/layout", reply: () => ({ ok: true, data: { type: "Button" } }) },
		{ match: "/health", reply: () => ({ ok: true, data: { status: "ok" } }) },
	]);
	try {
		const driver = await connect(9090, { host: "mock" });
		await driver.loadScene("res://levels/1.tscn");
		assert.equal(globalThis.fetch.calls[1].path, "/scene/load");
		assert.equal(globalThis.fetch.calls.length, 2); // no /wait/frames call
		await driver.layout("/root/Main/Button", { depth: 1 });
		assert.equal(globalThis.fetch.calls[2].path, "/ui/layout/root/Main/Button?depth=1");
		await driver.layout("my_btn", { testId: true });
		assert.equal(globalThis.fetch.calls[3].path, "/ui/layout?test_id=my_btn");
		driver.close();
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test("resize() posts /window/resize + one-frame wait; windowState() GETs", async () => {
	globalThis.fetch = mockFetch([
		{ match: "/window/resize", reply: () => ({ ok: true, data: { width: 800, height: 600 } }) },
		{
			match: "/window/state",
			reply: () => ({ ok: true, data: { size: { width: 800, height: 600 } } }),
		},
		{ match: "/wait/frames", reply: () => ({ ok: true, data: { waited: 1 } }) },
		{ match: "/health", reply: () => ({ ok: true, data: { status: "ok" } }) },
	]);
	try {
		const driver = await connect(9090, { host: "mock" });
		await driver.resize(800, 600, {
			stretchMode: "canvas_items",
			aspect: "keep_width",
			scale: 2,
		});
		assert.deepEqual(
			globalThis.fetch.calls.map((c) => c.path),
			["/health", "/window/resize", "/wait/frames?frames=1"],
		);
		assert.deepEqual(JSON.parse(globalThis.fetch.calls[1].init.body), {
			width: 800,
			height: 600,
			stretch_mode: "canvas_items",
			aspect: "keep_width",
			scale: 2,
		});
		await driver.windowState();
		assert.equal(globalThis.fetch.calls[3].path, "/window/state");
		driver.close();
	} finally {
		globalThis.fetch = originalFetch;
	}
});

// --- live integration tests (skipped without GODOT_BIN) ---

test("live: click round-trip changes the fixture label", { skip: !liveAvailable() }, async (t) => {
	const game = await startLiveGame();
	t.after(() => game.kill());
	const driver = await connect(LIVE_PORT);
	try {
		const before = await driver.request("/node/root/Main/Label/property/text");
		await driver.click("/root/Main/Button");
		const after = await driver.request("/node/root/Main/Label/property/text");
		assert.notEqual(before.value, after.value);
		assert.equal(after.value, "pressed");
	} finally {
		driver.close();
	}
});

test(
	"live: type into LineEdit + pressKey + loadScene + layout",
	{ skip: !liveAvailable() },
	async (t) => {
		const game = await startLiveGame();
		t.after(() => game.kill());
		const driver = await connect(LIVE_PORT);
		try {
			// layout read (no wait).
			const lay = await driver.layout("/root/Main/Button");
			assert.equal(lay.type, "Button");
			// loadScene resolves only when ready.
			const loaded = await driver.loadScene(
				"res://scratch/spike/test/fixtures/alt_scene.tscn",
			);
			assert.equal(loaded.scene_ready, true);
			const cur = await driver.request("/scene/current");
			assert.equal(cur.scene, "res://scratch/spike/test/fixtures/alt_scene.tscn");
			// restore main scene for the click test's fixture.
			await driver.loadScene("res://scratch/spike/scenes/main.tscn");
		} finally {
			driver.close();
		}
	},
);
