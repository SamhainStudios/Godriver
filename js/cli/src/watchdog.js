import http from "node:http";

export class Watchdog {
	/**
	 * @param {Object} options
	 * @param {number} [options.port=9999]
	 * @param {number} [options.intervalMs=5000]
	 * @param {number} [options.timeoutMs=15000]
	 * @param {import("./launcher.js").GodotLauncher} options.launcher
	 * @param {(reason: string) => void} [options.onFailure]
	 */
	constructor(options) {
		this.port = options.port || parseInt(process.env.GODRIVER_PORT || "9999", 10);
		this.intervalMs = options.intervalMs || 5000;
		this.timeoutMs = options.timeoutMs || 15000;
		this.launcher = options.launcher;
		this.onFailure = options.onFailure || (() => {});
		this.timer = null;
		this.running = false;
		this.lastHealthyTime = Date.now();
	}

	start() {
		this.running = true;
		this.lastHealthyTime = Date.now();
		this.timer = setInterval(() => this.checkHealth(), this.intervalMs);
	}

	stop() {
		this.running = false;
		if (this.timer) {
			clearInterval(this.timer);
			this.timer = null;
		}
	}

	async checkHealth() {
		if (!this.running) return;

		// Check if launcher process exited
		if (this.launcher.process && this.launcher.process.exitCode !== null) {
			this.stop();
			const msg = `Godot process crashed unexpectedly with exit code ${this.launcher.process.exitCode}`;
			this.onFailure(msg);
			return;
		}

		const isHealthy = await new Promise((resolve) => {
			const req = http.get(`http://127.0.0.1:${this.port}/health`, { timeout: 2000 }, (res) => {
				if (res.statusCode === 200) {
					resolve(true);
				} else {
					resolve(false);
				}
			});
			req.on("error", () => resolve(false));
			req.on("timeout", () => {
				req.destroy();
				resolve(false);
			});
		});

		if (isHealthy) {
			this.lastHealthyTime = Date.now();
		} else {
			const elapsed = Date.now() - this.lastHealthyTime;
			if (elapsed >= this.timeoutMs) {
				this.stop();
				const logs = this.launcher.stderrLogs.join("");
				const msg = `Watchdog detected engine stall: /health unresponsive for ${elapsed}ms.\nGodot Stderr:\n${logs}`;
				this.launcher.stop();
				this.onFailure(msg);
			}
		}
	}
}
