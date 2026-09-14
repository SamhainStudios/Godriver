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
 * @property {number} [maxSockets] Deprecated / ignored connection pool limit.
 */

/**
 * @typedef {Object} SignalEmission
 * @property {string} target Canonical node path of the emitting node.
 * @property {string} signal Name of the signal emitted.
 * @property {Array<unknown>} args Arguments passed to the signal.
 * @property {number} timestamp Wall-clock timestamp when emitted.
 * @property {number} frame Engine process frame index when emitted.
 * @property {number} seq Monotonic emission sequence number.
 */

/**
 * @typedef {Object} PropertySchema
 * @property {string} name Property name.
 * @property {string} type SPEC §4/§8 type string (e.g. "int", "float", "String", "Vector2").
 * @property {unknown} value Current property value.
 */

/**
 * @typedef {Object} Driver
 * @property {(path: string, init?: {method?: string, body?: unknown, timeoutMs?: number}) => Promise<unknown>} request
 *   Low-level typed request: unwraps the envelope, returns `data`, throws typed errors.
 * @property {() => Promise<{status: string, godot_version: string, spec_version: string}>} health
 *   GET /health — read server status.
 * @property {(opts?: {tweenMode?: "kill"|"await"}) => Promise<{reloaded_scene: string, scene_ready: boolean, missing_autoloads?: string[]}>} reset
 *   POST /reset — full scenario isolation reset.
 * @property {(target: string, opts?: {testId?: boolean}) => Promise<{injected: boolean, target: string, viewport?: string}>} click
 *   POST /input/click + one-frame auto-wait (SPEC §6). target = node path, or test_id when opts.testId.
 * @property {(target: string, text: string, opts?: {testId?: boolean}) => Promise<{injected: boolean, target: string}>} type
 *   POST /input/type + one-frame auto-wait.
 * @property {(key: string, opts?: {target?: string, testId?: boolean}) => Promise<{injected: boolean, key: string, target?: string}>} pressKey
 * @property {(key: string, opts?: {target?: string, testId?: boolean}) => Promise<{injected: boolean, key: string, target?: string, pressed: boolean}>} keyDown
 *   POST /input/key_down - inject only the pressed event; held state becomes observable (GTD-054).
 * @property {(key: string, opts?: {target?: string, testId?: boolean}) => Promise<{injected: boolean, key: string, target?: string, pressed: boolean}>} keyUp
 *   POST /input/key_up - inject only the released event (GTD-054).
 *   POST /input/key + one-frame auto-wait; opts.target focuses a Control first.
 * @property {(path: string, opts?: {tweenMode?: "kill"|"await"|"none"}) => Promise<{loaded: string, scene_ready: boolean}>} loadScene
 *   POST /scene/load — resolves only when the new scene is ready.
 * @property {(target: string, opts?: {testId?: boolean, depth?: number}) => Promise<Record<string, unknown>>} layout
 * @property {(target: string, name: string, value: unknown, opts?: {testId?: boolean}) => Promise<Record<string, unknown>>} setProperty
 *   POST /node/<path>/property/<name> - write a node property (GTD-055).
 *   test_id targets are resolved via /node?test_id first. Enables game-state
 *   seeding: teleport the player, set counters, update labels.
 * @property {(width: number, height: number, opts?: {stretchMode?: "disabled"|"canvas_items"|"viewport", aspect?: "ignore"|"keep"|"keep_width"|"keep_height"|"expand", scale?: number}) => Promise<Record<string, unknown>>} resize
 *   POST /window/resize - change the root window size and optionally override stretch config (GTD-053).
 * @property {() => Promise<Record<string, unknown>>} windowState
 *   GET /window/state - effective window size + stretch configuration (GTD-053).
 *   GET /ui/layout — Control layout inspection.
 * @property {(target: string, signal: string, opts?: {testId?: boolean}) => Promise<{watched: boolean, target: string, signal: string}>} watchSignal
 *   POST /signal/watch — connect a signal observer.
 * @property {(opts?: {target?: string, signal?: string}) => Promise<{emissions: SignalEmission[]}>} pollSignals
 *   GET /signal/poll — poll buffered signal emissions.
 * @property {(target: string, signal: string, opts?: {testId?: boolean, timeout?: number, timeoutMs?: number}) => Promise<{signaled: boolean, emission?: SignalEmission, reset?: boolean, timed_out?: boolean}>} waitSignal
 *   POST /signal/wait — worker long-poll wait until signal fires.
 * @property {(target: string, opts?: {testId?: boolean, expected?: boolean, timeoutMs?: number, pollIntervalMs?: number}) => Promise<{target: string, actual: boolean, expected: boolean, passed: boolean}>} assertVisible
 *   Auto-retrying /assert/visible assertion.
 * @property {(target: string, opts?: {testId?: boolean, expected?: boolean, timeoutMs?: number, pollIntervalMs?: number}) => Promise<{target: string, actual: boolean, expected: boolean, passed: boolean}>} assertEnabled
 *   Auto-retrying /assert/enabled assertion.
 * @property {(target: string, property: string, expected: unknown, opts?: {testId?: boolean, timeoutMs?: number, pollIntervalMs?: number}) => Promise<{target: string, property: string, actual: unknown, expected: unknown, passed: boolean}>} assertProperty
 *   Auto-retrying /assert/property assertion.
 * @property {(target: string, expected: unknown, opts?: {testId?: boolean, timeoutMs?: number, pollIntervalMs?: number}) => Promise<{target: string, property: string, actual: unknown, expected: unknown, passed: boolean}>} assertText
 *   Auto-retrying /assert/property assertion for the "text" property.
 * @property {(frames?: number) => Promise<{frames: number, elapsed: number}>} waitFrames
 *   GET /wait/frames?frames=N — advance N process_frames.
 * @property {(opts?: {timeout?: number, timeoutMs?: number}) => Promise<{tweens_remaining: number}>} waitTween
 *   POST /wait/tween — wait for all active SceneTree tweens to finish.
 * @property {(target: string, opts?: {testId?: boolean, timeoutMs?: number}) => Promise<{target: string, actual: boolean, expected: boolean, passed: boolean}>} waitVisible
 *   Alias for assertVisible(target, { ...opts, expected: true })
 * @property {(target: string, opts?: {testId?: boolean, timeoutMs?: number}) => Promise<{target: string, actual: boolean, expected: boolean, passed: boolean}>} waitHidden
 *   Alias for assertVisible(target, { ...opts, expected: false })
 * @property {(target?: string) => Promise<{autoload?: string, target?: string, values: Record<string, unknown>}>} getState
 *   GET /state — read script-declared state properties.
 * @property {(target?: string) => Promise<{autoload?: string, target?: string, properties: PropertySchema[]}>} getSchema
 *   GET /state/schema — read property type declarations.
 * @property {(values: Record<string, unknown>, target?: string) => Promise<{autoload?: string, target?: string, updated: string[]}>} setState
 *   POST /state/set — mutate target properties with SPEC §8 coercion rules.
 * @property {(seed: number) => Promise<{seeded: boolean, seed: number}>} setSeed
 *   POST /dev/seed — seed global RNG.
 * @property {(scale: number) => Promise<{time_scale: number}>} setTimeScale
 *   POST /dev/time_scale — update Engine.time_scale.
 * @property {(enabled: boolean) => Promise<{paused: boolean}>} setPause
 *   POST /dev/pause — toggle SceneTree pause.
 * @property {(slot: string) => Promise<{slot: string, loaded: boolean, path?: string}>} loadSaveSlot
 *   POST /dev/save/load — verify/load save slot.
 * @property {(opts?: {format?: "binary"|"base64", hdr?: boolean, viewport?: string}) => Promise<any>} screenshot
 *   POST /screenshot/capture — capture full viewport PNG.
 * @property {(target?: string, opts?: {testId?: boolean, rect?: {x: number, y: number, w: number, h: number}, format?: "binary"|"base64", hdr?: boolean, viewport?: string}) => Promise<any>} screenshotRegion
 *   POST /screenshot/region — capture node bounds or explicit rect crop as PNG.
 * @property {() => void} close Release underlying agent resources.
 */

/**
 * Perform one enveloped request against the addon using native fetch.
 *
 * @param {string} base "http://127.0.0.1:9090" style base URL.
 * @param {string} token Bearer token ("" = auth disabled).
 * @param {number} timeoutMs AbortSignal timeout.
 * @param {string} path Endpoint path, e.g. "/health".
 * @param {{method?: string, body?: unknown}} [init]
 * @returns {Promise<unknown>} The envelope's `data` payload.
 * @throws {DriverError} Envelope error (ok:false) mapped to typed error.
 * @throws {ConnectionError} Network-level failure or timeout.
 * @throws {DriverError} with code "INTERNAL_ERROR" on malformed envelopes.
 */
async function _request(base, token, timeoutMs, path, init = {}) {
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
		signal: AbortSignal.timeout(timeoutMs),
		headers,
	};
	if (init.body !== undefined) {
		req.body = JSON.stringify(init.body);
	}
	/** @type {Response} */
	let res;
	try {
		res = await fetch(base + path, req);
	} catch (e) {
		if (
			/** @type {Error} */ (e).name === "TimeoutError" ||
			/** @type {Error} */ (e).name === "AbortError"
		) {
			throw new ConnectionError(`request to ${path} timed out after ${timeoutMs}ms`, e);
		}
		throw new ConnectionError(
			`addon unreachable at ${base} (${/** @type {Error} */ (e).message})`,
			e,
		);
	}
	const text = await res.text();
	/** @type {any} */
	let envelope;
	try {
		envelope = JSON.parse(text);
	} catch {
		throw new DriverError(
			"INTERNAL_ERROR",
			`malformed envelope from ${path} (HTTP ${res.status})`,
			res.status,
		);
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
 * Perform a binary request (e.g. screenshot) expecting raw bytes or JSON error.
 *
 * @param {string} base Base URL.
 * @param {string} token Bearer token.
 * @param {number} timeoutMs AbortSignal timeout.
 * @param {string} path Endpoint path.
 * @param {{method?: string, body?: unknown}} [init]
 * @returns {Promise<{buffer: Uint8Array, width: number, height: number, contentType: string}>}
 */
async function _requestBinary(base, token, timeoutMs, path, init = {}) {
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
		signal: AbortSignal.timeout(timeoutMs),
		headers,
	};
	if (init.body !== undefined) {
		req.body = JSON.stringify(init.body);
	}
	/** @type {Response} */
	let res;
	try {
		res = await fetch(base + path, req);
	} catch (e) {
		if (
			/** @type {Error} */ (e).name === "TimeoutError" ||
			/** @type {Error} */ (e).name === "AbortError"
		) {
			throw new ConnectionError(`request to ${path} timed out after ${timeoutMs}ms`, e);
		}
		throw new ConnectionError(
			`addon unreachable at ${base} (${/** @type {Error} */ (e).message})`,
			e,
		);
	}

	const contentType = res.headers.get("content-type") || "";
	if (contentType.includes("application/json")) {
		const text = await res.text();
		let envelope;
		try {
			envelope = JSON.parse(text);
		} catch {
			throw new DriverError(
				"INTERNAL_ERROR",
				`malformed envelope from ${path} (HTTP ${res.status})`,
				res.status,
			);
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

	if (!res.ok) {
		throw new DriverError("HTTP_ERROR", `request failed with HTTP ${res.status}`, res.status);
	}

	const arrayBuffer = await res.arrayBuffer();
	return {
		buffer: new Uint8Array(arrayBuffer),
		width: parseInt(res.headers.get("x-image-width") || "0", 10),
		height: parseInt(res.headers.get("x-image-height") || "0", 10),
		contentType,
	};
}

/**
 * Poll an assertion endpoint until passed is true or timeoutMs deadline expires.
 *
 * @param {string} base Base URL.
 * @param {string} token Bearer token.
 * @param {string} path Endpoint path.
 * @param {Record<string, unknown>} body Request body.
 * @param {number} [timeoutMs=3000] Polling deadline in ms.
 * @param {number} [pollIntervalMs=50] Polling interval in ms.
 * @returns {Promise<any>} Response data object when passed.
 */
async function _pollAssertion(base, token, path, body, timeoutMs = 3000, pollIntervalMs = 50) {
	const deadline = Date.now() + timeoutMs;
	let lastData = null;
	while (Date.now() <= deadline) {
		const data = /** @type {any} */ (
			await _request(base, token, 2000, path, { method: "POST", body })
		);
		lastData = data;
		if (data && data.passed === true) {
			return data;
		}
		await new Promise((r) => setTimeout(r, pollIntervalMs));
	}
	const targetLabel = String(body.path || body.test_id || "target");
	throw new DriverError(
		"ASSERTION_FAILED",
		`Assertion ${path} failed on ${targetLabel} after ${timeoutMs}ms (expected: ${JSON.stringify(body.expected)}, actual: ${JSON.stringify(lastData?.actual)})`,
		200,
		lastData,
	);
}

/**
 * Normalize target string or options object. Supports "test_id:foo" prefix syntax.
 * @param {string|null} target
 * @param {{testId?: boolean, [k: string]: unknown}} [opts]
 * @returns {{target: string|null, testId: boolean}}
 */
function _parseTarget(target, opts = {}) {
	if (typeof target === "string" && target.startsWith("test_id:")) {
		return { target: target.slice(8), testId: true };
	}
	return { target, testId: !!opts?.testId };
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
	const base = `http://${host}:${port}`;
	const healthData =
		/** @type {{status: string, godot_version: string, spec_version: string}} */ (
			await _request(base, token, timeoutMs, "/health")
		);

	/** @type {Driver} */
	const driver = {
		/** @type {Driver["request"]} */
		request: (path, init = {}) =>
			_request(base, token, init.timeoutMs ?? timeoutMs, path, init),
		/** @type {Driver["health"]} */
		health: () => Promise.resolve(healthData),
		/** @type {Driver["reset"]} */
		reset: (opts = {}) => {
			/** @type {Record<string, unknown>} */
			const body = {};
			if (opts.tweenMode) {
				body.tween_mode = opts.tweenMode;
			}
			return /** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, "/reset", { method: "POST", body })
			);
		},
		/** @type {Driver["click"]} */
		click: (target, opts = {}) =>
			/** @type {Promise<any>} */ (
				_interact(base, token, timeoutMs, "/input/click", target, opts)
			),
		/** @type {Driver["type"]} */
		type: (target, text, opts = {}) =>
			/** @type {Promise<any>} */ (
				_interact(base, token, timeoutMs, "/input/type", target, { ...opts, text })
			),
		/** @type {Driver["pressKey"]} */
		pressKey: (key, opts = {}) =>
			/** @type {Promise<any>} */ (
				_interact(base, token, timeoutMs, "/input/key", opts.target ?? null, {
					...opts,
					key,
				})
			),
		/** @type {Driver["keyDown"]} */
		keyDown: (key, opts = {}) =>
			/** @type {Promise<any>} */ (
				_interact(base, token, timeoutMs, "/input/key_down", opts.target ?? null, {
					...opts,
					key,
				})
			),
		/** @type {Driver["keyUp"]} */
		keyUp: (key, opts = {}) =>
			/** @type {Promise<any>} */ (
				_interact(base, token, timeoutMs, "/input/key_up", opts.target ?? null, {
					...opts,
					key,
				})
			),
		/** @type {Driver["loadScene"]} */
		loadScene: (path, opts = {}) => {
			const normalizedPath =
				path.startsWith("res://") || path.startsWith("user://")
					? path
					: `res://${path.replace(/^\//, "")}`;
			/** @type {Record<string, unknown>} */
			const body = { path: normalizedPath };
			if (opts.tweenMode) {
				body.tween_mode = opts.tweenMode;
			}
			return /** @type {Promise<{loaded: string, scene_ready: boolean}>} */ (
				_request(base, token, timeoutMs, "/scene/load", { method: "POST", body })
			);
		},
		/** @type {Driver["layout"]} */
		layout: (target, opts = {}) => {
			const parsed = _parseTarget(target, opts);
			let suffix = "";
			if (parsed.testId) {
				suffix = `?test_id=${encodeURIComponent(parsed.target ?? "")}`;
				if (opts.depth) {
					suffix += `&depth=${opts.depth}`;
				}
			} else {
				suffix = `/${String(parsed.target ?? "").replace(/^\//, "")}`;
				if (opts.depth) {
					suffix += `?depth=${opts.depth}`;
				}
			}
			return /** @type {Promise<Record<string, unknown>>} */ (
				_request(base, token, timeoutMs, `/ui/layout${suffix}`)
			);
		},
		/** @type {Driver["setProperty"]} */
		setProperty: async (target, name, value, opts = {}) => {
			const parsed = _parseTarget(target, opts);
			let path;
			if (parsed.testId) {
				const found = await _request(base, token, timeoutMs, `/node?test_id=${encodeURIComponent(parsed.target ?? "")}`);
				path = /** @type {Record<string, unknown>} */ (found).path;
			} else {
				path = String(parsed.target ?? "").replace(/^\//, "");
			}
			return /** @type {Promise<Record<string, unknown>>} */ (
				_request(base, token, timeoutMs, `/node/${path}/property/${encodeURIComponent(name)}`, {
					method: "POST",
					body: { value },
				})
			);
		},
		/** @type {Driver["resize"]} */
		resize: (width, height, opts = {}) => {
			/** @type {Record<string, unknown>} */
			const body = { width, height };
			if (opts.stretchMode) {
				body.stretch_mode = opts.stretchMode;
			}
			if (opts.aspect) {
				body.aspect = opts.aspect;
			}
			if (opts.scale !== undefined) {
				body.scale = opts.scale;
			}
			return /** @type {Promise<Record<string, unknown>>} */ (
				_interact(base, token, timeoutMs, "/window/resize", null, { ...opts, body })
			);
		},
		/** @type {Driver["windowState"]} */
		windowState: () =>
			/** @type {Promise<Record<string, unknown>>} */ (
				_request(base, token, timeoutMs, "/window/state")
			),
		/** @type {Driver["watchSignal"]} */
		watchSignal: (target, signal, opts = {}) => {
			const parsed = _parseTarget(target, opts);
			/** @type {Record<string, unknown>} */
			const body = { signal };
			if (parsed.testId) {
				body.test_id = parsed.target;
			} else {
				body.path = parsed.target;
			}
			return /** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, "/signal/watch", { method: "POST", body })
			);
		},
		/** @type {Driver["pollSignals"]} */
		pollSignals: (opts = {}) => {
			const q = new URLSearchParams();
			if (opts.target) {
				q.set("target", opts.target);
			}
			if (opts.signal) {
				q.set("signal", opts.signal);
			}
			const qs = q.toString();
			return /** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, `/signal/poll${qs ? "?" + qs : ""}`)
			);
		},
		/** @type {Driver["waitSignal"]} */
		waitSignal: (target, signal, opts = {}) => {
			const parsed = _parseTarget(target, opts);
			/** @type {Record<string, unknown>} */
			const body = { signal };
			if (parsed.testId) {
				body.test_id = parsed.target;
			} else {
				body.path = parsed.target;
			}
			if (opts.timeout !== undefined) {
				body.timeout = opts.timeout;
			}
			const effectiveTimeout =
				opts.timeoutMs ?? (opts.timeout ? (opts.timeout + 2) * 1000 : 35000);
			return /** @type {Promise<any>} */ (
				_request(base, token, effectiveTimeout, "/signal/wait", { method: "POST", body })
			);
		},
		/** @type {Driver["assertVisible"]} */
		assertVisible: (target, opts = {}) => {
			const parsed = _parseTarget(target, opts);
			/** @type {Record<string, unknown>} */
			const body = { expected: opts.expected ?? true };
			if (parsed.testId) {
				body.test_id = parsed.target;
			} else {
				body.path = parsed.target;
			}
			return /** @type {Promise<any>} */ (
				_pollAssertion(
					base,
					token,
					"/assert/visible",
					body,
					opts.timeoutMs ?? 3000,
					opts.pollIntervalMs ?? 50,
				)
			);
		},
		/** @type {Driver["assertEnabled"]} */
		assertEnabled: (target, opts = {}) => {
			const parsed = _parseTarget(target, opts);
			/** @type {Record<string, unknown>} */
			const body = { expected: opts.expected ?? true };
			if (parsed.testId) {
				body.test_id = parsed.target;
			} else {
				body.path = parsed.target;
			}
			return /** @type {Promise<any>} */ (
				_pollAssertion(
					base,
					token,
					"/assert/enabled",
					body,
					opts.timeoutMs ?? 3000,
					opts.pollIntervalMs ?? 50,
				)
			);
		},
		/** @type {Driver["assertProperty"]} */
		assertProperty: (target, property, expected, opts = {}) => {
			const parsed = _parseTarget(target, opts);
			/** @type {Record<string, unknown>} */
			const body = { property, expected };
			if (parsed.testId) {
				body.test_id = parsed.target;
			} else {
				body.path = parsed.target;
			}
			return /** @type {Promise<any>} */ (
				_pollAssertion(
					base,
					token,
					"/assert/property",
					body,
					opts.timeoutMs ?? 3000,
					opts.pollIntervalMs ?? 50,
				)
			);
		},
		/** @type {Driver["assertText"]} */
		assertText: (target, expected, opts = {}) =>
			driver.assertProperty(target, "text", expected, opts),
		/** @type {Driver["waitFrames"]} */
		waitFrames: (frames = 1) =>
			/** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, `/wait/frames?frames=${frames}`)
			),
		/** @type {Driver["waitTween"]} */
		waitTween: (opts = {}) => {
			/** @type {Record<string, unknown>} */
			const body = {};
			if (opts.timeout !== undefined) {
				body.timeout = opts.timeout;
			}
			return /** @type {Promise<any>} */ (
				_request(base, token, opts.timeoutMs ?? timeoutMs, "/wait/tween", {
					method: "POST",
					body,
				})
			);
		},
		/** @type {Driver["waitVisible"]} */
		waitVisible: (target, opts = {}) =>
			driver.assertVisible(target, { ...opts, expected: true }),
		/** @type {Driver["waitHidden"]} */
		waitHidden: (target, opts = {}) =>
			driver.assertVisible(target, { ...opts, expected: false }),
		/** @type {Driver["getState"]} */
		getState: (target) =>
			/** @type {Promise<any>} */ (
				_request(
					base,
					token,
					timeoutMs,
					`/state${target ? "?target=" + encodeURIComponent(target) : ""}`,
				)
			),
		/** @type {Driver["getSchema"]} */
		getSchema: (target) =>
			/** @type {Promise<any>} */ (
				_request(
					base,
					token,
					timeoutMs,
					`/state/schema${target ? "?target=" + encodeURIComponent(target) : ""}`,
				)
			),
		/** @type {Driver["setState"]} */
		setState: (values, target) => {
			/** @type {Record<string, unknown>} */
			const body = { values };
			if (target) {
				body.target = target;
			}
			return /** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, "/state/set", { method: "POST", body })
			);
		},
		/** @type {Driver["setSeed"]} */
		setSeed: (seed) =>
			/** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, "/dev/seed", { method: "POST", body: { seed } })
			),
		/** @type {Driver["setTimeScale"]} */
		setTimeScale: (scale) =>
			/** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, "/dev/time_scale", {
					method: "POST",
					body: { scale },
				})
			),
		/** @type {Driver["setPause"]} */
		setPause: (enabled) =>
			/** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, "/dev/pause", {
					method: "POST",
					body: { enabled },
				})
			),
		/** @type {Driver["loadSaveSlot"]} */
		loadSaveSlot: (slot) =>
			/** @type {Promise<any>} */ (
				_request(base, token, timeoutMs, "/dev/save/load", {
					method: "POST",
					body: { slot },
				})
			),
		/** @type {Driver["screenshot"]} */
		screenshot: (opts = {}) => {
			const format = opts.format ?? "binary";
			/** @type {Record<string, unknown>} */
			const body = {};
			if (opts.format !== undefined) {
				body.format = opts.format;
			}
			if (opts.hdr !== undefined) {
				body.hdr = opts.hdr;
			}
			if (opts.viewport !== undefined) {
				body.viewport = opts.viewport;
			}

			if (format === "base64") {
				return /** @type {Promise<any>} */ (
					_request(base, token, timeoutMs, "/screenshot/capture", {
						method: "POST",
						body,
					})
				);
			}
			return /** @type {Promise<any>} */ (
				_requestBinary(base, token, timeoutMs, "/screenshot/capture", {
					method: "POST",
					body,
				})
			);
		},
		/** @type {Driver["screenshotRegion"]} */
		screenshotRegion: (target, opts = {}) => {
			const format = opts.format ?? "binary";
			/** @type {Record<string, unknown>} */
			const body = {};
			if (target) {
				const parsed = _parseTarget(target, opts);
				if (parsed.testId) {
					body.test_id = parsed.target;
				} else {
					body.path = parsed.target;
				}
			}
			if (opts.rect !== undefined) {
				body.rect = opts.rect;
			}
			if (opts.format !== undefined) {
				body.format = opts.format;
			}
			if (opts.hdr !== undefined) {
				body.hdr = opts.hdr;
			}
			if (opts.viewport !== undefined) {
				body.viewport = opts.viewport;
			}

			if (format === "base64") {
				return /** @type {Promise<any>} */ (
					_request(base, token, timeoutMs, "/screenshot/region", { method: "POST", body })
				);
			}
			return /** @type {Promise<any>} */ (
				_requestBinary(base, token, timeoutMs, "/screenshot/region", {
					method: "POST",
					body,
				})
			);
		},
		/** @type {Driver["close"]} */
		close: () => {},
	};
	return driver;
}

/**
 * Inject an input event, then auto-wait exactly one frame.
 *
 * @param {string} base Base URL.
 * @param {string} token Bearer token.
 * @param {number} timeoutMs Per-request timeout.
 * @param {string} path Endpoint path.
 * @param {string|null} rawTarget Node path, or null when targeting by test_id.
 * @param {{testId?: boolean, [k: string]: unknown}} opts
 * @returns {Promise<unknown>} The endpoint's `data` payload.
 */
async function _interact(base, token, timeoutMs, path, rawTarget, opts = {}) {
	const parsed = _parseTarget(rawTarget, opts);
	/** @type {Record<string, unknown>} */
	const body = opts.body ? { ...opts.body } : {};
	if (parsed.testId && parsed.target != null) {
		body.test_id = parsed.target;
	} else if (parsed.target != null) {
		body.path = parsed.target;
	}
	for (const k of /** @type {const} */ (["text", "key"])) {
		if (opts[k] !== undefined) {
			body[k] = opts[k];
		}
	}
	const data = await _request(base, token, timeoutMs, path, { method: "POST", body });
	await _request(base, token, timeoutMs, "/wait/frames?frames=1");
	return data;
}
