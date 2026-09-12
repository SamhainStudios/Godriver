import { GodotLauncher } from "./launcher.js";
import { Watchdog } from "./watchdog.js";
import { spawn } from "node:child_process";

export { GodotLauncher, Watchdog };

/**
 * CLI Runner entrypoint
 * @param {string[]} argv
 * @returns {Promise<number>} Exit code (0=success, 1=test fail, 2=infra error)
 */
export async function runCli(argv = process.argv.slice(2)) {
	let godotPath = process.env.GODOT_BIN || "godot";
	let projectPath = ".";
	let port = parseInt(process.env.GODRIVER_PORT || "9999", 10);
	let headless = true;
	let cucumberArgs = [];

	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === "--godot" && argv[i + 1]) {
			godotPath = argv[++i];
		} else if (arg === "--project" && argv[i + 1]) {
			projectPath = argv[++i];
		} else if (arg === "--port" && argv[i + 1]) {
			port = parseInt(argv[++i], 10);
		} else if (arg === "--no-headless") {
			headless = false;
		} else {
			cucumberArgs.push(arg);
		}
	}

	const launcher = new GodotLauncher({
		godotPath,
		projectPath,
		port,
		headless,
	});

	let infraError = false;

	const watchdog = new Watchdog({
		port,
		launcher,
		onFailure: (msg) => {
			console.error(`\n[GODDRIVER WATCHDOG ERROR] ${msg}`);
			infraError = true;
		},
	});

	try {
		console.log(`[godriver] Launching Godot (${godotPath}) at path: ${projectPath} on port ${port}...`);
		await launcher.start();
		console.log(`[godriver] Godot instance ready. Starting watchdog...`);
		watchdog.start();

		// Execute test suite / cucumber runner if cucumber args or default test runner specified
		const testCode = await new Promise((resolve) => {
			// If @cucumber/cucumber is run or fallback test runner
			const npx = process.platform === "win32" ? "npx.cmd" : "npx";
			const testProc = spawn(npx, ["cucumber-js", ...cucumberArgs], {
				stdio: "inherit",
				env: { ...process.env, GODRIVER_PORT: port.toString() },
			});

			testProc.on("error", (err) => {
				console.error(`[godriver] Failed to spawn test runner: ${err.message}`);
				resolve(2);
			});

			testProc.on("exit", (code) => {
				resolve(code ?? 0);
			});
		});

		watchdog.stop();
		launcher.stop();

		if (infraError) {
			return 2;
		}
		return testCode === 0 ? 0 : 1;
	} catch (err) {
		watchdog.stop();
		launcher.stop();
		console.error(`[godriver] Infrastructure Failure: ${err.message}`);
		return 2;
	}
}
