import { test } from "node:test";
import assert from "node:assert/strict";
import { connect } from "../src/client.js";

test("live integration against running Godot instance", async () => {
	const driver = await connect(9999);

	// 1. Health check
	const health = await driver.health();
	assert.equal(health.status, "ok");

	// 2. Assertions
	const vis = await driver.assertVisible("/root/Main");
	assert.equal(vis.passed, true);

	const en = await driver.assertEnabled("/root/Main");
	assert.equal(en.passed, true);

	const prop = await driver.assertProperty("/root/Main", "name", "Main");
	assert.equal(prop.passed, true);

	// 3. State methods
	const schema = await driver.getSchema("/root/Main");
	assert.ok(schema);

	// 4. Dev determinism
	const seedRes = await driver.setSeed(12345);
	assert.equal(seedRes.seeded, true);

	const tsRes = await driver.setTimeScale(1.5);
	assert.equal(tsRes.time_scale, 1.5);

	const pauseRes = await driver.setPause(false);
	assert.equal(pauseRes.paused, false);

	// 5. Signals
	const watchRes = await driver.watchSignal("/root/Main", "ready");
	assert.ok(watchRes);

	const pollRes = await driver.pollSignals({ target: "/root/Main" });
	assert.ok(pollRes);

	driver.close();
});
