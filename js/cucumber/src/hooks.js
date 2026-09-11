/**
 * @godriver/cucumber — Lifecycle hook helpers for Cucumber scenarios.
 */

/**
 * Setup hooks with a Cucumber framework instance (Before, After, etc.).
 *
 * @param {Object} cucumberFramework Cucumber export object carrying Before, After, etc.
 * @param {Object} [options]
 * @param {boolean} [options.autoReset=true] Automatically call /reset before each scenario.
 */
export function registerHooks(cucumberFramework, options = {}) {
	const { Before, After } = cucumberFramework;
	const autoReset = options.autoReset ?? true;

	Before(async function () {
		// Initialize driver connection for the scenario
		const driver = await this.initDriver();
		if (autoReset) {
			await driver.request("/reset", { method: "POST", body: { tween_mode: "kill" } });
		}
	});

	After(async function () {
		// Clean up driver connection
		await this.destroyDriver();
	});
}
