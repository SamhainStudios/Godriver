/**
 * Unit tests for @godriver/cucumber package (world, hooks, steps binding).
 * Uses node:test (built-in, zero deps).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { GodotWorld, registerHooks, registerSteps } from "../src/index.js";

test("GodotWorld initializes default options and environment overrides", () => {
	process.env.GODRIVER_PORT = "9999";
	process.env.GODRIVER_HOST = "127.0.0.1";
	try {
		const world = new GodotWorld();
		assert.equal(world.port, 9999);
		assert.equal(world.host, "127.0.0.1");
		assert.equal(world.driver, null);
	} finally {
		delete process.env.GODRIVER_PORT;
		delete process.env.GODRIVER_HOST;
	}
});

test("registerHooks registers Before and After hooks", () => {
	const registered = [];
	const cucumberMock = {
		Before: (fn) => registered.push({ type: "Before", fn }),
		After: (fn) => registered.push({ type: "After", fn }),
	};
	registerHooks(cucumberMock);
	assert.equal(registered.length, 2);
	assert.equal(registered[0].type, "Before");
	assert.equal(registered[1].type, "After");
});

test("registerSteps registers all ~15 step definitions", () => {
	const steps = [];
	const cucumberMock = {
		Given: (pattern, fn) => steps.push({ type: "Given", pattern, fn }),
		When: (pattern, fn) => steps.push({ type: "When", pattern, fn }),
		Then: (pattern, fn) => steps.push({ type: "Then", pattern, fn }),
	};
	registerSteps(cucumberMock);
	assert.ok(steps.length >= 15);

	const patterns = steps.map((s) => s.pattern);
	assert.ok(patterns.includes("I load scene {string}"));
	assert.ok(patterns.includes("I click {string}"));
	assert.ok(patterns.includes("I should see {string}"));
	assert.ok(patterns.includes("I watch signal {string} on {string}"));
	assert.ok(patterns.includes("I set time scale to {float}"));
});
