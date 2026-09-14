import { GodotLauncher } from "./launcher.js";
import { Watchdog } from "./watchdog.js";
import { spawn } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { generateScreens, renderScreensModule } from "./codegen.js";

export { GodotLauncher, Watchdog, generateScreens, renderScreensModule };

/**
 * `godriver generate` - connect to a running game and emit a Screen Objects
 * module (GTD-056).
 *
 * @param {{ port?: number, host?: string, out?: string }} [opts]
 * @returns {Promise<number>} exit code
 */
export async function runGenerate(opts = {}) {
	const { connect } = await import("@godriver/core");
	const port = opts.port ?? parseInt(process.env.GODRIVER_PORT || "9090", 10);
	const host = opts.host ?? "127.0.0.1";
	const out = opts.out ?? "screens.generated.js";
	const driver = await connect(port, { host });
	try {
		const health = await driver.request("/health");
		const entries = await generateScreens(driver);
		const source = renderScreensModule(entries, { godotVersion: String(health.godot_version ?? "unknown") });
		await writeFile(out, source);
		console.log(`[godriver] generated ${out}: ${entries.length} test_id entries`);
		return 0;
	} finally {
		driver.close();
	}
}

/**
 * CLI Runner entrypoint
 * @param {string[]} argv
 * @returns {Promise<number>} Exit code (0=success, 1=test fail, 2=infra error)
 */
export async function runCli(argv = process.argv.slice(2)) {
	if (argv[0] === "generate") {
		const opts = {};
		for (let i = 1; i < argv.length; i++) {
			if (argv[i] === "--port" && argv[i + 1]) {
				opts.port = parseInt(argv[++i], 10);
			} else if (argv[i] === "--host" && argv[i + 1]) {
				opts.host = argv[++i];
			} else if (argv[i] === "--out" && argv[i + 1]) {
				opts.out = argv[++i];
			}
		}
		return runGenerate(opts);
	}
	let godotPath = process.env.GODOT_BIN || "godot";
	let projectPath = ".";
	let port = parseInt(process.env.GODRIVER_PORT || "9999", 10);
	let headless = true;
	const cucumberArgs = [];

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
		console.log(
			`[godriver] Launching Godot (${godotPath}) at path: ${projectPath} on port ${port}...`,
		);
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
