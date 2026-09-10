/**
 * GTD-018 — smoke: @godriver/core querying a live game.
 *
 * Usage: node examples/smoke.mjs [port]   (default 9090)
 * Requires a game running with the test-driver addon active:
 *   Godot --headless --path . -- --test-driver
 *
 * Exercises the SPEC §5 read surface end-to-end: /health, /node/<path>,
 * /node/<path>/property/<name>, /scene/current, /state. Exits 0 when every
 * response matches its SPEC shape; typed errors otherwise.
 */
// Relative import: examples/ sits outside the js/ npm workspace, so a
// package-name import would need an install step. This keeps the smoke
// script zero-install while still using only the public client API.
import { connect, DriverError, ConnectionError } from "../js/core/src/client.js";

const port = Number(process.argv[2] ?? process.env.GODRIVER_PORT ?? 9090);

/** @param {string} label @param {unknown} value */
function show(label, value) {
	console.log(`${label}: ${JSON.stringify(value)}`);
}

try {
	const driver = await connect(port);
	try {
		// 1. /health — SPEC §5.1
		const health = await driver.health();
		show("HEALTH", health);
		if (health.status !== "ok") throw new Error("health status not ok");

		// 2. /node/<path> — SPEC §5.2 summary shape
		const scene = await driver.request("/scene/current");
		show("SCENE", scene);
		const sceneNode = String(scene.node); // e.g. "/root/Main"
		const node = await driver.request(`/node${sceneNode}`);
		for (const key of ["path", "name", "type", "test_id", "child_count", "children", "script"]) {
			if (!(key in node)) throw new Error(`node summary missing key '${key}'`);
		}
		show("NODE", node);

		// 3. property read — SPEC §5.2 (first child's name property; Godot
		//    reports node names as StringName, which §4 serializes as a string)
		const firstChild = String(node.children[0]);
		const prop = await driver.request(`/node${sceneNode}/${firstChild}/property/name`);
		show("PROPERTY", prop);
		if (prop.type !== "String" && prop.type !== "StringName") {
			throw new Error(`expected String/StringName property, got ${prop.type}`);
		}
		if (prop.value !== firstChild) throw new Error(`property value mismatch: ${prop.value}`);

		// 4. typed error path — unknown node must throw DriverError NODE_NOT_FOUND
		try {
			await driver.request("/node/root/DefinitelyNotHere");
			throw new Error("expected NODE_NOT_FOUND, got success");
		} catch (e) {
			if (!(e instanceof DriverError) || e.code !== "NODE_NOT_FOUND") throw e;
			show("TYPED_ERROR", { code: e.code, status: e.status });
		}

		// 5. /state — SPEC §5.8 (409 STATE_AUTOLOAD_MISSING is a valid shape too)
		try {
			const state = await driver.request("/state");
			show("STATE", state);
		} catch (e) {
			if (!(e instanceof DriverError) || e.code !== "STATE_AUTOLOAD_MISSING") throw e;
			show("STATE", { state_autoload: "not configured", code: e.code });
		}

		// 6. click() round-trip — the fixture Button flips its Label (GTD-026).
		//    Reset first so the label starts in its initial state. 409
		//    STATE_AUTOLOAD_MISSING is fine (reset completed without the state
		//    step — the dev project has no GameState autoload).
		try {
			await driver.request("/reset", { method: "POST", body: {} });
		} catch (e) {
			if (!(e instanceof DriverError) || e.code !== "STATE_AUTOLOAD_MISSING") throw e;
		}
		await driver.click("/root/Main/Button");
		const label = await driver.request("/node/root/Main/Label/property/text");
		show("CLICK", label);
		if (label.value !== "pressed") throw new Error(`click round-trip failed: ${label.value}`);

		console.log("SMOKE_OK");
	} finally {
		driver.close();
		// Let undici's UV handles finish closing before process exit —
		// destroying the agent and exiting immediately trips a libuv
		// assertion on Windows (uv_async closing race).
		await new Promise((r) => setTimeout(r, 50));
	}
} catch (e) {
	if (e instanceof ConnectionError) {
		console.error(`SMOKE_FAIL: game not reachable on port ${port} — is it running with -- --test-driver?`);
	} else if (e instanceof DriverError) {
		console.error(`SMOKE_FAIL: ${e.code} (HTTP ${e.status}): ${e.message}`);
	} else {
		console.error(`SMOKE_FAIL: ${/** @type {Error} */ (e).message}`);
	}
	process.exit(1);
}
