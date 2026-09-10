/**
 * @godriver/core — portable HTTP client for the Godot Test Driver addon.
 *
 * Contract: SPEC v0.1 response envelope `{ok, data}` / `{ok, error:{code, message, details}}`.
 * Zero runner dependencies; ES modules only; Node 18+ (built-in fetch/undici).
 *
 * @module @godriver/core
 */

/**
 * Typed error carrying the SPEC Appendix A error code.
 */
export class DriverError extends Error {
	/**
	 * @param {string} code SPEC Appendix A error code (e.g. "NODE_NOT_FOUND").
	 * @param {string} message Human-readable message from the addon.
	 * @param {number} status HTTP status code.
	 * @param {{}|null} [details] Optional structured details from the addon.
	 */
	constructor(code, message, status, details = null) {
		super(message);
		/** @type {string} */
		this.name = "DriverError";
		/** @type {string} SPEC Appendix A error code. */
		this.code = code;
		/** @type {number} HTTP status. */
		this.status = status;
		/** @type {{}|null} */
		this.details = details;
	}
}

/**
 * Thrown when the addon is unreachable (connection refused, timeout, socket reset).
 */
export class ConnectionError extends Error {
	/**
	 * @param {string} message
	 * @param {unknown} [cause] The underlying fetch error.
	 */
	constructor(message, cause = undefined) {
		super(message);
		/** @type {string} */
		this.name = "ConnectionError";
		// @ts-ignore - ES2022 cause is fine at runtime; lib may be lower in type-test.
		this.cause = cause;
	}
}

/**
 * @typedef {Object} ConnectOptions
 * @property {string} [host="127.0.0.1"] Host the game listens on (addon binds 127.0.0.1).
 * @property {string} [token=""] Bearer token when the addon was launched with --test-driver-token.
 * @property {number} [timeoutMs=5000] Per-request timeout in milliseconds.
 * @property {number} [maxSockets=16] Undici agent pool size — MUST be >= the addon's
 *   max_blocked_waits cap (8, SPEC §6.1) or long-polls starve parallel requests.
 */

/**
 * @typedef {Object} Driver
 * @property {(path: string, init?: {method?: string, body?: unknown, timeoutMs?: number}) => Promise<unknown>} request
 *   Low-level typed request: unwraps the envelope, returns `data`, throws typed errors.
 * @property {() => Promise<{status: string, godot_version: string, spec_version: string}>} health
 * @property {(target: string, opts?: {testId?: boolean}) => Promise<unknown>} click
 *   POST /input/click + one-frame auto-wait (SPEC §6). target = node path, or
 *   test_id when opts.testId.
 * @property {(target: string, text: string, opts?: {testId?: boolean}) => Promise<unknown>} type
 *   POST /input/type + one-frame auto-wait.
 * @property {(key: string, opts?: {target?: string, testId?: boolean}) => Promise<unknown>} pressKey
 *   POST /input/key + one-frame auto-wait; opts.target focuses a Control first.
 * @property {(path: string) => Promise<{loaded: string, scene_ready: boolean}>} loadScene
 *   POST /scene/load — resolves only when the new scene is ready (server-side
 *   readiness contract, no extra wait).
 * @property {(target: string, opts?: {testId?: boolean, depth?: number}) => Promise<unknown>} layout
 *   GET /ui/layout — read, no wait.
 * @property {() => void} close Release the underlying agent resources.
 */

/**
 * Perform one enveloped request against the addon.
 *
 * @param {string} base "http://127.0.0.1:9090" style base URL.
 * @param {string} token Bearer token ("" = auth disabled).
 * @param {number} timeoutMs AbortSignal timeout.
 * @param {import("undici").Agent} agent Undici agent (pool sizing).
 * @param {string} path Endpoint path, e.g. "/health".
 * @param {{method?: string, body?: unknown}} [init]
 * @returns {Promise<unknown>} The envelope's `data` payload.
 * @throws {DriverError} Envelope error (ok:false) mapped to typed error.
 * @throws {ConnectionError} Network-level failure or timeout.
 * @throws {DriverError} with code "INTERNAL_ERROR" on malformed envelopes.
 */
async function _request(base, token, timeoutMs, agent, path, init = {}) {
	const method = init.method ?? "GET";
	/** @type {Record<string, string>} */
	const headers = {};
	if (token !== "") {
		headers.authorization = `Bearer ${token}`;
	}
	if (init.body !== undefined) {
		headers["content-type"] = "application/json";
	}
	/** @type {RequestInit} */
	const req = {
		method,
		// @ts-ignore - undici dispatcher is the documented pool-sizing hook.
		dispatcher: agent,
		signal: AbortSignal.timeout(timeoutMs),
		headers,
	};
	if (init.body !== undefined) {
		(req).body = JSON.stringify(init.body);
	}
	/** @type {Response} */
	let res;
	try {
		res = await fetch(base + path, req);
	} catch (e) {
		if (/** @type {Error} */ (e).name === "TimeoutError" || /** @type {Error} */ (e).name === "AbortError") {
			throw new ConnectionError(`request to ${path} timed out after ${timeoutMs}ms`, e);
		}
		throw new ConnectionError(`addon unreachable at ${base} (${/** @type {Error} */ (e).message})`, e);
	}
	const text = await res.text();
	/** @type {any} */
	let envelope;
	try {
		envelope = JSON.parse(text);
	} catch {
		throw new DriverError("INTERNAL_ERROR", `malformed envelope from ${path} (HTTP ${res.status})`, res.status);
	}
	if (envelope.ok === true) {
		return envelope.data;
	}
	const err = envelope.error ?? {};
	throw new DriverError(
		String(err.code ?? "INTERNAL_ERROR"),
		String(err.message ?? `request to ${path} failed (HTTP ${res.status})`),
		res.status,
		err.details ?? null,
	);
}

/**
 * Connect to a running game with the test-driver addon active.
 *
 * Verifies `/health` before returning the driver handle; a refused connection
 * surfaces as {@link ConnectionError} (not a silent later failure).
 *
 * @param {number} port Port the addon listens on (default 9090; GODRIVER_PORT when ephemeral).
 * @param {ConnectOptions} [options]
 * @returns {Promise<Driver>}
 */
export async function connect(port, options = {}) {
	const host = options.host ?? "127.0.0.1";
	const token = options.token ?? "";
	const timeoutMs = options.timeoutMs ?? 5000;
	// SPEC §6.1: the pool must be sized explicitly — Node's default undici
	// pool is small (4-6) and long-polls (max_blocked_waits up to 8) would
	// starve parallel requests in CI.
	const maxSockets = options.maxSockets ?? 16;
	const { Agent } = await import("undici");
	/** @type {import("undici").Agent} */
	const agent = new Agent({ connections: maxSockets });
	const base = `http://${host}:${port}`;
	// Verify liveness up front: connection-refused must fail HERE, typed.
	const healthData = /** @type {{status: string, godot_version: string, spec_version: string}} */ (
		await _request(base, token, timeoutMs, agent, "/health")
	);
	return {
		/** @type {Driver["request"]} */
		request: (path, init = {}) => _request(base, token, init.timeoutMs ?? timeoutMs, agent, path, init),
		/** @type {Driver["health"]} */
		health: () => Promise.resolve(healthData),
		/** @type {Driver["click"]} */
		click: (target, opts = {}) => _interact(base, token, timeoutMs, agent, "/input/click", target, opts),
		/** @type {Driver["type"]} */
		type: (target, text, opts = {}) => _interact(base, token, timeoutMs, agent, "/input/type", target, { ...opts, text }),
		/** @type {Driver["pressKey"]} */
		pressKey: (key, opts = {}) => _interact(base, token, timeoutMs, agent, "/input/key", opts.target ?? null, { ...opts, key }),
		/** @type {Driver["loadScene"]} */
		loadScene: (path) =>
			/** @type {Promise<{loaded: string, scene_ready: boolean}>} */
			(_request(base, token, timeoutMs, agent, "/scene/load", { method: "POST", body: { path } })),
		/** @type {Driver["layout"]} */
		layout: (target, opts = {}) => {
			let suffix = "";
			if (opts.testId) {
				suffix = `?test_id=${encodeURIComponent(target)}`;
				if (opts.depth) suffix += `&depth=${opts.depth}`;
			} else {
				suffix = `/${String(target).replace(/^\//, "")}`;
				if (opts.depth) suffix += `?depth=${opts.depth}`;
			}
			return _request(base, token, timeoutMs, agent, `/ui/layout${suffix}`);
		},
		close: () => {
			agent.destroy?.();
		},
	};
}

/**
 * Inject an input event, then auto-wait exactly one frame (SPEC §6 timing
 * contract: 200 = injected only; effects land on the next engine tick).
 * The wait uses the addon's frame-wait endpoint — no hidden sleeps.
 *
 * @param {string} base Base URL.
 * @param {string} token Bearer token.
 * @param {number} timeoutMs Per-request timeout.
 * @param {import("undici").Agent} agent Undici agent.
 * @param {string} path Endpoint path.
 * @param {string|null} target Node path, or null when targeting by test_id.
 * @param {{testId?: boolean, [k: string]: unknown}} opts
 * @returns {Promise<unknown>} The endpoint's `data` payload.
 */
async function _interact(base, token, timeoutMs, agent, path, target, opts) {
	/** @type {Record<string, unknown>} */
	const body = {};
	if (opts.testId && target != null) {
		body.test_id = target;
	} else if (target != null) {
		body.path = target;
	}
	for (const k of /** @type {const} */ (["text", "key"])) {
		if (opts[k] !== undefined) {
			body[k] = opts[k];
		}
	}
	const data = await _request(base, token, timeoutMs, agent, path, { method: "POST", body });
	await _request(base, token, timeoutMs, agent, "/wait/frames?frames=1");
	return data;
}
