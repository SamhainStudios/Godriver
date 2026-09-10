/**
 * GTD-026 — live-game test harness: spawn Godot headless with the test-driver
 * addon active, poll /health (10s deadline), provide teardown kill.
 *
 * Skipped when GODOT_BIN is absent (CI wires it in GTD-042):
 *   GODOT_BIN=C:\path\to\Godot_v4.7.2-stable_win64.exe node --test js/core/test/
 */
import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";

export const GODOT_BIN = process.env.GODOT_BIN ?? "";
export const LIVE_PORT = 9177; // fixed test port (away from 9090 dev default)

/** @returns {boolean} whether live tests can run in this environment */
export function liveAvailable() {
	return GODOT_BIN !== "";
}

/**
 * Spawn the dev project headless with the addon active on LIVE_PORT.
 * Resolves when /health answers; rejects after a 10s deadline.
 * @returns {Promise<{proc: import("node:child_process").ChildProcess, kill: () => Promise<void>}>}
 */
export async function startLiveGame() {
	if (!liveAvailable()) {
		throw new Error("GODOT_BIN not set — live tests skipped");
	}
	const proc = spawn(GODOT_BIN, [
		"--headless", "--path", process.cwd(),
		"--", "--test-driver", `--test-driver-port=${LIVE_PORT}`,
	], { stdio: ["ignore", "pipe", "pipe"] });
	proc.stdout.on("data", () => {});
	proc.stderr.on("data", () => {});
	const deadline = Date.now() + 10000;
	while (Date.now() < deadline) {
		try {
			const res = await fetch(`http://127.0.0.1:${LIVE_PORT}/health`, { signal: AbortSignal.timeout(1000) });
			if (res.ok) {
				return {
					proc,
					kill: () => new Promise((resolve) => {
						proc.once("exit", () => resolve());
						proc.kill();
						setTimeout(resolve, 2000).unref?.();
					}),
				};
			}
		} catch {
			// not up yet — retry
		}
		await delay(250);
	}
	proc.kill();
	throw new Error("live game did not answer /health within 10s");
}
