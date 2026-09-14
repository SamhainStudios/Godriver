import { test } from "node:test";
import assert from "node:assert/strict";
import { connect } from "../src/client.js";

const PORT = parseInt(process.env.GODRIVER_PORT || "9999", 10);
const LIVE = process.env.GODRIVER_LIVE === "1" || process.env.GODRIVER_LIVE === "true";

test(
	"headless endpoint sweep (live Godot instance)",
	{ skip: !LIVE && "Set GODRIVER_LIVE=1 to run against active Godot engine" },
	async () => {
		const driver = await connect(PORT);

		// 1. Health check
		const health = await driver.health();
		assert.equal(health.status, "ok");
		assert.ok(health.godot_version);

		// 2. Node & Scene Inspection
		const scene = await driver.request("/scene/current");
		assert.ok(scene);

		const rootNode = await driver.request("/node/root");
		assert.ok(rootNode);

		// 3. State & Assertions
		const vis = await driver.assertVisible("/root");
		assert.equal(vis.passed, true);

		const en = await driver.assertEnabled("/root");
		assert.equal(en.passed, true);

		const stateSchema = await driver.getSchema("/root");
		assert.ok(stateSchema);

		// 4. Input Injection under --headless
		// Input key/type injection
		await driver.pressKey("ui_accept");

		// 5. Signals
		await driver.watchSignal("/root", "tree_entered");
		const polls = await driver.pollSignals({ target: "/root" });
		assert.ok(Array.isArray(polls.emissions));

		// 6. Dev determinism controls
		const seeded = await driver.setSeed(42);
		assert.equal(seeded.seeded, true);

		const timeScaled = await driver.setTimeScale(1.0);
		assert.equal(timeScaled.time_scale, 1.0);

		const pauseState = await driver.setPause(false);
		assert.equal(pauseState.paused, false);

		// 7. Screenshot endpoints under --headless must reject with HEADLESS_RENDERING_DISABLED
		await assert.rejects(
			driver.screenshot(),
			(e) => e.code === "HEADLESS_RENDERING_DISABLED" && e.status === 400,
		);
		await assert.rejects(
			driver.screenshotRegion("/root"),
			(e) => e.code === "HEADLESS_RENDERING_DISABLED" && e.status === 400,
		);

		driver.close();
	},
);
