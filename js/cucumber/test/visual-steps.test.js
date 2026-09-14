/**
 * GTD-052 tests: visual step definitions (registration + behavior with a mocked driver).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { registerVisualSteps } from "../src/steps/visual.js";
import { solidPng } from "@godriver/visual";

/** Capture the Then registrations from a mocked Cucumber framework. @returns {{steps: Array<{pattern: string, fn: Function}>, cucumberMock: Object}} */
function captureSteps() {
	const steps = [];
	const cucumberMock = {
		Given: (pattern, fn) => steps.push({ pattern, fn }),
		When: (pattern, fn) => steps.push({ pattern, fn }),
		Then: (pattern, fn) => steps.push({ pattern, fn }),
	};
	registerVisualSteps(cucumberMock);
	return { steps, cucumberMock };
}

/** @param {Buffer} png @returns {import("@godriver/visual").AssertOptions["screenshot"]} */
function captureFn(png) {
	return async () => ({
		buffer: new Uint8Array(png),
		width: 32,
		height: 32,
		contentType: "image/png",
	});
}

/** World mock with a driver whose screenshot returns a fixed PNG. @param {Buffer} png @returns {{initDriver: () => Promise<Object>}} */
function worldWith(png) {
	const driver = { screenshot: captureFn(png) };
	return { initDriver: async () => driver };
}

test("registerVisualSteps registers the three baseline steps", () => {
	const { steps } = captureSteps();
	const patterns = steps.map((s) => s.pattern);
	assert.ok(patterns.includes("the screen should match baseline {string}"));
	assert.ok(patterns.includes("the screen should match baseline {string} at node {string}"));
	assert.ok(patterns.includes("the screen should match baseline {string} at test_id {string}"));
});

test("baseline step: first run with UPDATE_BASELINE creates baseline, second run passes", async () => {
	const { steps } = captureSteps();
	const root = await mkdtemp(join(tmpdir(), "godriver-cuke-"));
	process.env.GODRIVER_BASELINES_DIR = join(root, "baselines");
	process.env.GODRIVER_ARTIFACTS_DIR = join(root, "artifacts", "visual");
	process.env.UPDATE_BASELINE = "true";
	try {
		const png = await solidPng(32, 32, "#336699");
		const step = steps.find(
			(s) => s.pattern === "the screen should match baseline {string}",
		).fn;
		await step.call(worldWith(png), "menu");
		delete process.env.UPDATE_BASELINE;
		// Same capture now matches.
		await step.call(worldWith(png), "menu");
		const meta = JSON.parse(await readFile(join(root, "baselines", "menu.json"), "utf8"));
		assert.equal(meta.driver, "cucumber");
	} finally {
		delete process.env.UPDATE_BASELINE;
		delete process.env.GODRIVER_BASELINES_DIR;
		delete process.env.GODRIVER_ARTIFACTS_DIR;
		await rm(root, { recursive: true, force: true });
	}
});

test("baseline step: mismatch throws with report path", async () => {
	const { steps } = captureSteps();
	const root = await mkdtemp(join(tmpdir(), "godriver-cuke-"));
	process.env.GODRIVER_BASELINES_DIR = join(root, "baselines");
	process.env.GODRIVER_ARTIFACTS_DIR = join(root, "artifacts", "visual");
	try {
		const baseline = await solidPng(32, 32, "#336699");
		const actual = await solidPng(32, 32, "#ff0000");
		const step = steps.find(
			(s) => s.pattern === "the screen should match baseline {string}",
		).fn;
		process.env.UPDATE_BASELINE = "true";
		await step.call(worldWith(baseline), "diffy");
		delete process.env.UPDATE_BASELINE;
		await assert.rejects(() => step.call(worldWith(actual), "diffy"), /report\.html/);
		await readFile(join(root, "artifacts", "visual", "diffy", "report.html"));
	} finally {
		delete process.env.GODRIVER_BASELINES_DIR;
		delete process.env.GODRIVER_ARTIFACTS_DIR;
		await rm(root, { recursive: true, force: true });
	}
});

test("baseline step: test_id variant routes through screenshotRegion with testId", async () => {
	const { steps } = captureSteps();
	const root = await mkdtemp(join(tmpdir(), "godriver-cuke-"));
	process.env.GODRIVER_BASELINES_DIR = join(root, "baselines");
	process.env.GODRIVER_ARTIFACTS_DIR = join(root, "artifacts", "visual");
	process.env.UPDATE_BASELINE = "true";
	try {
		const png = await solidPng(32, 32, "#336699");
		/** @type {Array<{target: string, opts: Object}>} */
		const calls = [];
		const driver = {
			screenshotRegion: async (target, opts = {}) => {
				calls.push({ target, opts });
				return captureFn(png)({});
			},
		};
		const step = steps.find(
			(s) => s.pattern === "the screen should match baseline {string} at test_id {string}",
		).fn;
		await step.call({ initDriver: async () => driver }, "hud", "hud_root");
		assert.equal(calls.length, 1);
		assert.equal(calls[0].target, "hud_root");
		assert.equal(calls[0].opts.testId, true);
	} finally {
		delete process.env.UPDATE_BASELINE;
		delete process.env.GODRIVER_BASELINES_DIR;
		delete process.env.GODRIVER_ARTIFACTS_DIR;
		await rm(root, { recursive: true, force: true });
	}
});
