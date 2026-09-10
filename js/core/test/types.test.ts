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
