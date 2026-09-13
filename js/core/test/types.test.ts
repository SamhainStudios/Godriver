/**
 * Type-test file — compiled by `tsc --noEmit` in CI (GTD-017 acceptance).
 * Asserts the JSDoc-inferred surface of @godriver/core; contains no runtime code.
 */
import { connect, type Driver, type DriverError, type ConnectionError } from "../src/client.js";

// connect signature
const p: Promise<Driver> = connect(9090);
const p2: Promise<Driver> = connect(9091, { token: "s3cret", timeoutMs: 2000, maxSockets: 32 });

// Driver surface
async function use(d: Driver): Promise<void> {
	const data: unknown = await d.request("/node/root/Main");
	const data2: unknown = await d.request("/reset", { method: "POST", body: { tween_mode: "kill" } });
	const h: { status: string; godot_version: string; spec_version: string } = await d.health();

	// Inputs & Scene
	await d.click("/root/Button", { testId: false });
	await d.type("/root/Input", "hello");
	await d.pressKey("ui_accept");
	// Reset & Scene
	await d.reset();
	await d.reset({ tweenMode: "await" });
	await d.loadScene("res://main.tscn", { tweenMode: "kill" });
	await d.layout("/root/Main");

	// Signals
	await d.watchSignal("/root/Main", "pressed");
	await d.pollSignals({ target: "/root/Main" });
	await d.waitSignal("/root/Main", "pressed", { timeout: 5 });

	// Assertions & Waits
	await d.assertVisible("/root/Main");
	await d.assertEnabled("/root/Main");
	await d.assertProperty("/root/Main", "name", "Main");
	await d.assertText("/root/Main", "Hello");
	await d.waitFrames(2);
	await d.waitTween({ timeout: 1000 });
	await d.waitVisible("/root/Main");
	await d.waitHidden("/root/Main");

	// State & Dev
	await d.getState();
	await d.getSchema();
	await d.setState({ hp: 100 });
	await d.setSeed(42);
	await d.setTimeScale(1.5);
	await d.setPause(false);
	await d.loadSaveSlot("slot1");

	d.close();
}

// Error classes carry the SPEC fields.
function handle(e: DriverError): string {
	const c: string = e.code;
	const s: number = e.status;
	const det: object | null = e.details;
	return `${c}:${s}`;
}

function isConn(e: ConnectionError): boolean {
	return e.name === "ConnectionError";
}

export { p, p2, use, handle, isConn };
