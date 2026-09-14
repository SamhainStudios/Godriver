/**
 * Visual-regression step definitions for @godriver/cucumber (GTD-052).
 *
 * Requires @godriver/visual (peer). Import and register alongside registerSteps:
 *
 *   import { registerSteps } from "@godriver/cucumber";
 *   import { registerVisualSteps } from "@godriver/cucumber/steps/visual";
 *   registerSteps(Cucumber); registerVisualSteps(Cucumber);
 *
 * Baselines live under GODRIVER_BASELINES_DIR (default "tests/baselines"),
 * mismatch artifacts under GODRIVER_ARTIFACTS_DIR (default "artifacts/visual").
 * Set UPDATE_BASELINE=true to (re)capture baselines.
 */
import { BaselineStore, assertMatchesBaseline } from "@godriver/visual";

/**
 * Register visual step definitions with Cucumber.
 *
 * @param {Object} cucumberFramework Cucumber export object carrying Then.
 */
export function registerVisualSteps(cucumberFramework) {
	const { Then } = cucumberFramework;

	/**
	 * @param {Object} world Cucumber World (must expose initDriver()).
	 * @param {string} name baseline name
	 * @param {{ target?: string, testId?: boolean }} [region] optional region capture
	 */
	async function assertBaseline(world, name, region = {}) {
		const driver = await world.initDriver();
		const store = new BaselineStore({
			dir: process.env.GODRIVER_BASELINES_DIR ?? "tests/baselines",
			artifactsDir: process.env.GODRIVER_ARTIFACTS_DIR ?? "artifacts/visual",
		});
		/** @type {import("@godriver/visual").AssertOptions["screenshot"]} */
		const screenshot = region.target
			? (opts = {}) =>
					driver.screenshotRegion(region.target, {
						testId: region.testId === true,
						...opts,
					})
			: (opts = {}) => driver.screenshot(opts);
		await assertMatchesBaseline(store, name, { screenshot, driverLabel: "cucumber" });
	}

	Then("the screen should match baseline {string}", async function (name) {
		await assertBaseline(this, name);
	});

	Then(
		"the screen should match baseline {string} at node {string}",
		async function (name, target) {
			await assertBaseline(this, name, { target });
		},
	);

	Then(
		"the screen should match baseline {string} at test_id {string}",
		async function (name, testId) {
			await assertBaseline(this, name, { target: testId, testId: true });
		},
	);
}
