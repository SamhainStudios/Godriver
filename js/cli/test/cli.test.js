import { test } from "node:test";
import assert from "node:assert/strict";
import { GodotLauncher } from "../src/launcher.js";
import { Watchdog } from "../src/watchdog.js";

test("GodotLauncher defaults and configuration", () => {
	const launcher = new GodotLauncher({
		godotPath: "custom-godot",
		projectPath: "./my_project",
		port: 8888,
		headless: true,
	});

	assert.equal(launcher.godotPath, "custom-godot");
	assert.equal(launcher.projectPath, "./my_project");
	assert.equal(launcher.port, 8888);
	assert.equal(launcher.headless, true);
});

test("Watchdog triggers failure callback on stall", async () => {
	const mockLauncher = {
		process: { exitCode: null },
		stderrLogs: ["Engine deadlock warning\n"],
		stop() {},
	};

	let failureReported = null;

	const watchdog = new Watchdog({
		port: 59999, // Unused port so health check fails
		intervalMs: 50,
		timeoutMs: 100,
		launcher: mockLauncher,
		onFailure: (msg) => {
			failureReported = msg;
		},
	});

	watchdog.start();
	await new Promise((r) => setTimeout(r, 250));

	assert.ok(failureReported);
	assert.match(failureReported, /Watchdog detected engine stall/);
});

test("Watchdog detects unexpected process exit", async () => {
	const mockLauncher = {
		process: { exitCode: 139 }, // Segmentation fault
		stderrLogs: ["SIGSEGV crash\n"],
		stop() {},
	};

	let failureReported = null;

	const watchdog = new Watchdog({
		port: 59999,
		intervalMs: 50,
		timeoutMs: 500,
		launcher: mockLauncher,
		onFailure: (msg) => {
			failureReported = msg;
		},
	});

	watchdog.start();
	await new Promise((r) => setTimeout(r, 100));

	assert.ok(failureReported);
	assert.match(failureReported, /crashed unexpectedly with exit code 139/);
});
