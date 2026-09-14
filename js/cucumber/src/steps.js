/**
 * @godriver/cucumber — Built-in step definitions for Godriver.
 */

/**
 * Register core step definitions with Cucumber.
 *
 * @param {Object} cucumberFramework Cucumber export object carrying Given, When, Then.
 */
export function registerSteps(cucumberFramework) {
	const { Given, When, Then } = cucumberFramework;

	// --- Navigation ---
	Given("I load scene {string}", async function (scenePath) {
		const driver = await this.initDriver();
		await driver.loadScene(scenePath);
	});

	// --- Interaction ---
	When("I click {string}", async function (target) {
		const driver = await this.initDriver();
		await driver.click(target);
	});

	When("I click test_id {string}", async function (testId) {
		const driver = await this.initDriver();
		await driver.click(testId, { testId: true });
	});

	When("I type {string} into {string}", async function (text, target) {
		const driver = await this.initDriver();
		await driver.type(target, text);
	});

	When("I press key {string}", async function (key) {
		const driver = await this.initDriver();
		await driver.pressKey(key);
	});

	// --- Assertions ---
	Then("I should see {string}", async function (target) {
		const driver = await this.initDriver();
		await driver.assertVisible(target, { expected: true });
	});

	Then("I should not see {string}", async function (target) {
		const driver = await this.initDriver();
		await driver.assertVisible(target, { expected: false });
	});

	Then("node {string} should be enabled", async function (target) {
		const driver = await this.initDriver();
		await driver.assertEnabled(target, { expected: true });
	});

	Then(
		"node {string} property {string} should be {string}",
		async function (target, property, expectedValue) {
			const driver = await this.initDriver();
			await driver.assertProperty(target, property, expectedValue);
		},
	);

	// --- Signals ---
	When("I watch signal {string} on {string}", async function (signalName, target) {
		const driver = await this.initDriver();
		await driver.watchSignal(target, signalName);
	});

	Then("I wait for signal {string} on {string}", async function (signalName, target) {
		const driver = await this.initDriver();
		await driver.waitSignal(target, signalName);
	});

	// --- State & Dev ---
	When("I set state {string} to {string}", async function (key, value) {
		const driver = await this.initDriver();
		await driver.setState({ [key]: value });
	});

	When("I set time scale to {float}", async function (scale) {
		const driver = await this.initDriver();
		await driver.setTimeScale(scale);
	});

	When("I pause the game", async function () {
		const driver = await this.initDriver();
		await driver.setPause(true);
	});

	When("I unpause the game", async function () {
		const driver = await this.initDriver();
		await driver.setPause(false);
	});
}
