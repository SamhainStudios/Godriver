import { spawn } from "node:child_process";
import http from "node:http";

export class GodotLauncher {
	/**
	 * @param {Object} options
	 * @param {string} [options.godotPath="godot"]
	 * @param {string} [options.projectPath="."]
	 * @param {number} [options.port=9999]
	 * @param {boolean} [options.headless=true]
	 * @param {string[]} [options.extraArgs=[]]
	 */
	constructor(options = {}) {
		this.godotPath = options.godotPath || process.env.GODOT_BIN || "godot";
		this.projectPath = options.projectPath || ".";
		this.port = options.port || parseInt(process.env.GODRIVER_PORT || "9999", 10);
		this.headless = options.headless !== false;
		this.extraArgs = options.extraArgs || [];
		/** @type {import("node:child_process").ChildProcess | null} */
		this.process = null;
		this.stderrLogs = [];
		this.stdoutLogs = [];
	}

	/**
	 * Launch the Godot process.
	 */
	async start() {
		const args = [
			"--path",
			this.projectPath,
			"--test-driver",
			`--test-driver-port=${this.port}`,
		];
		if (this.headless) {
			args.unshift("--headless");
		}
		args.push(...this.extraArgs);

		this.process = spawn(this.godotPath, args, {
			stdio: ["ignore", "pipe", "pipe"],
			env: { ...process.env },
		});

		this.process.stdout?.on("data", (chunk) => {
			const text = chunk.toString();
			this.stdoutLogs.push(text);
		});

		this.process.stderr?.on("data", (chunk) => {
			const text = chunk.toString();
			this.stderrLogs.push(text);
		});

		this.process.on("error", (err) => {
			this.stderrLogs.push(`Process spawn error: ${err.message}\n`);
		});

		// Wait until /health returns 200 ok
		await this.waitForReady(15000);
	}

	/**
	 * Poll /health until server responds or timeout.
	 * @param {number} timeoutMs
	 */
	async waitForReady(timeoutMs = 15000) {
		const startTime = Date.now();
		while (Date.now() - startTime < timeoutMs) {
			if (this.process && this.process.exitCode !== null) {
				throw new Error(
					`Godot process exited prematurely with code ${this.process.exitCode}`,
				);
			}
			try {
				const isHealthy = await new Promise((resolve) => {
					const req = http.get(
						`http://127.0.0.1:${this.port}/health`,
						{ timeout: 1000 },
						(res) => {
							if (res.statusCode === 200) {
								let body = "";
								res.on("data", (c) => (body += c));
								res.on("end", () => {
									try {
										const json = JSON.parse(body);
										resolve(json?.data?.status === "ok");
									} catch {
										resolve(false);
									}
								});
							} else {
								resolve(false);
							}
						},
					);
					req.on("error", () => resolve(false));
					req.on("timeout", () => {
						req.destroy();
						resolve(false);
					});
				});

				if (isHealthy) {
					return;
				}
			} catch {
				// retry
			}
			await new Promise((r) => setTimeout(r, 200));
		}

		this.stop();
		const logs = this.stderrLogs.join("");
		throw new Error(`Godot engine did not become ready within ${timeoutMs}ms.\nLogs:\n${logs}`);
	}

	/**
	 * Stop the Godot process.
	 */
	stop() {
		if (this.process && this.process.exitCode === null) {
			this.process.kill("SIGTERM");
			setTimeout(() => {
				if (this.process && this.process.exitCode === null) {
					this.process.kill("SIGKILL");
				}
			}, 2000);
		}
	}
}
