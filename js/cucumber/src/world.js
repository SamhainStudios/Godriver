/**
 * @godriver/cucumber — Custom GodotWorld extending Cucumber World.
 *
 * Provides driver connection management and configuration options for BDD tests.
 */
import { connect } from "@godriver/core";

export class GodotWorld {
	/**
	 * @param {Object} [options]
	 * @param {number} [options.port]
	 * @param {string} [options.host]
	 * @param {string} [options.token]
	 * @param {number} [options.timeoutMs]
	 * @param {Record<string, unknown>} [options.parameters]
	 */
	constructor(options = {}) {
		const params = options.parameters || {};
		/** @type {number} */
		this.port = Number(params.port || process.env.GODRIVER_PORT || 9090);
		/** @type {string} */
		this.host = String(params.host || process.env.GODRIVER_HOST || "127.0.0.1");
		/** @type {string} */
		this.token = String(params.token || process.env.GODRIVER_TOKEN || "");
		/** @type {number} */
		this.timeoutMs = Number(params.timeoutMs || process.env.GODRIVER_TIMEOUT_MS || 5000);
		/** @type {import("@godriver/core").Driver|null} */
		this.driver = null;
	}

	/**
	 * Connect to the running Godot game server.
	 * @returns {Promise<import("@godriver/core").Driver>}
	 */
	async initDriver() {
		if (!this.driver) {
			this.driver = await connect(this.port, {
				host: this.host,
				token: this.token,
				timeoutMs: this.timeoutMs,
			});
		}
		return this.driver;
	}

	/**
	 * Release underlying driver connection resources.
	 */
	async destroyDriver() {
		if (this.driver) {
			this.driver.close();
			this.driver = null;
		}
	}
}
