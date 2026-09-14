/**
 * GTD-017 unit tests — mocked fetch (no live game; integration smoke = GTD-018).
 * Uses node:test (built-in, zero deps).
 */
import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { connect, DriverError, ConnectionError } from "../src/client.js";

/**
 * Install a global fetch mock with per-path responses.
 * @param {Record<string, {status: number, body: string}>} routes path → response
 *   (unknown paths fall back to the first entry).
 */
function mockFetch(routes) {
	const calls = [];
	const fallback = Object.values(routes)[0];
	const impl = async (url, _init) => {
		calls.push({ url, init: _init });
		const path = new URL(url).pathname;
		const r = routes[path] ?? fallback;
		const status = r.status ?? 200;
		return {
			status,
			ok: status >= 200 && status < 300,
			headers: {
				get: (name) => {
					const ln = name.toLowerCase();
					if (r.headers && r.headers[ln]) {
						return r.headers[ln];
					}
					if (ln === "content-type") {
						return r.contentType ?? "application/json";
					}
					return null;
				},
			},
			text: async () => r.body ?? "",
			arrayBuffer: async () => r.rawBuffer ?? Buffer.from(r.body ?? ""),
		};
	};
	const m = mock.method(globalThis, "fetch", impl);
	return { m, calls };
}

const HEALTH_OK = {
	status: 200,
	body: JSON.stringify({
		ok: true,
		data: { status: "ok", godot_version: "4.7.2", spec_version: "0.1" },
	}),
};

test("connect resolves and health returns data", async () => {
	const { m, calls } = mockFetch({ "/health": HEALTH_OK });
	try {
		const driver = await connect(9090);
		const h = await driver.health();
		assert.equal(h.status, "ok");
		assert.equal(h.godot_version, "4.7.2");
		assert.equal(h.spec_version, "0.1");
		assert.equal(calls.length, 1);
		assert.equal(calls[0].url, "http://127.0.0.1:9090/health");
	} finally {
		m.mock.restore();
	}
});

test("envelope error maps to typed DriverError with code/message/details", async () => {
	const { m } = mockFetch({
		"/health": HEALTH_OK,
		"/node/root/Nope": {
			status: 404,
			body: JSON.stringify({
				ok: false,
				error: {
					code: "NODE_NOT_FOUND",
					message: "no node at path /root/Nope",
					details: null,
				},
			}),
		},
	});
	try {
		const driver = await connect(9090);
		await assert.rejects(
			driver.request("/node/root/Nope"),
			(e) =>
				e instanceof DriverError &&
				e.code === "NODE_NOT_FOUND" &&
				e.status === 404 &&
				e.message.includes("/root/Nope"),
		);
	} finally {
		m.mock.restore();
	}
});

test("details survive the mapping", async () => {
	const { m } = mockFetch({
		"/health": HEALTH_OK,
		"/node": {
			status: 409,
			body: JSON.stringify({
				ok: false,
				error: {
					code: "AMBIGUOUS_TEST_ID",
					message: "2 matches",
					details: { matches: ["/root/A", "/root/B"] },
				},
			}),
		},
	});
	try {
		const driver = await connect(9090);
		await assert.rejects(
			driver.request("/node?test_id=dup"),
			(e) =>
				e instanceof DriverError &&
				e.code === "AMBIGUOUS_TEST_ID" &&
				e.details.matches.length === 2,
		);
	} finally {
		m.mock.restore();
	}
});

test("connection refused → ConnectionError", async () => {
	const m = mock.method(globalThis, "fetch", async () => {
		throw Object.assign(new Error("connect ECONNREFUSED"), { name: "TypeError" });
	});
	try {
		await assert.rejects(connect(9090), (e) => e instanceof ConnectionError);
	} finally {
		m.mock.restore();
	}
});

test("timeout → ConnectionError", async () => {
	// /health must succeed (connect verifies it); the timeout hits the target path.
	const m = mock.method(globalThis, "fetch", async (url) => {
		if (new URL(url).pathname !== "/health") {
			throw Object.assign(new Error("aborted"), { name: "TimeoutError" });
		}
		return { status: 200, text: async () => HEALTH_OK.body };
	});
	try {
		const driver = await connect(9090);
		await assert.rejects(
			driver.request("/wait/long"),
			(e) => e instanceof ConnectionError && e.message.includes("timed out"),
		);
	} finally {
		m.mock.restore();
	}
});

test("malformed envelope → DriverError INTERNAL_ERROR", async () => {
	const { m } = mockFetch({
		"/health": HEALTH_OK,
		"/broken": { status: 200, body: "not json at all" },
	});
	try {
		const driver = await connect(9090);
		await assert.rejects(
			driver.request("/broken"),
			(e) => e instanceof DriverError && e.code === "INTERNAL_ERROR",
		);
	} finally {
		m.mock.restore();
	}
});

test("bearer token header set when token configured", async () => {
	const { m, calls } = mockFetch({ "/health": HEALTH_OK });
	try {
		const driver = await connect(9090, { token: "s3cret" });
		await driver.request("/health");
		assert.equal(calls[1].init.headers.authorization, "Bearer s3cret");
	} finally {
		m.mock.restore();
	}
});

test("POST body serialized as JSON with content-type", async () => {
	const { m, calls } = mockFetch({
		"/health": HEALTH_OK,
		"/reset": { status: 200, body: JSON.stringify({ ok: true, data: {} }) },
	});
	try {
		const driver = await connect(9090);
		await driver.request("/reset", { method: "POST", body: { tween_mode: "kill" } });
		assert.equal(calls[1].init.method, "POST");
		assert.equal(calls[1].init.body, JSON.stringify({ tween_mode: "kill" }));
		assert.equal(calls[1].init.headers["content-type"], "application/json");
	} finally {
		m.mock.restore();
	}
});

test("signal methods send correct request bodies", async () => {
	const { m, calls } = mockFetch({
		"/health": HEALTH_OK,
		"/signal/watch": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { watched: true } }),
		},
		"/signal/poll": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { emissions: [] } }),
		},
		"/signal/wait": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { signaled: true } }),
		},
	});
	try {
		const driver = await connect(9090);
		await driver.watchSignal("/root/Main", "pressed");
		await driver.pollSignals({ target: "/root/Main" });
		await driver.waitSignal("/root/Main", "pressed", { timeout: 2 });
		assert.equal(calls.length, 4);
		assert.equal(JSON.parse(calls[1].init.body).signal, "pressed");
		assert.equal(calls[2].url.includes("target=%2Froot%2FMain"), true);
		assert.equal(JSON.parse(calls[3].init.body).timeout, 2);
	} finally {
		m.mock.restore();
	}
});

test("assertVisible polls until passed true", async () => {
	let attempt = 0;
	const m = mock.method(globalThis, "fetch", async (url, _init) => {
		const path = new URL(url).pathname;
		if (path === "/health") {
			return { status: 200, text: async () => HEALTH_OK.body };
		}
		attempt++;
		const passed = attempt >= 2;
		return {
			status: 200,
			text: async () =>
				JSON.stringify({
					ok: true,
					data: { target: "/root/Main", actual: passed, expected: true, passed },
				}),
		};
	});
	try {
		const driver = await connect(9090);
		const res = await driver.assertVisible("/root/Main", {
			timeoutMs: 1000,
			pollIntervalMs: 10,
		});
		assert.equal(res.passed, true);
		assert.equal(attempt, 2);
	} finally {
		m.mock.restore();
	}
});

test("assertVisible throws DriverError ASSERTION_FAILED on timeout", async () => {
	const m = mock.method(globalThis, "fetch", async (url) => {
		const path = new URL(url).pathname;
		if (path === "/health") {
			return { status: 200, text: async () => HEALTH_OK.body };
		}
		return {
			status: 200,
			text: async () =>
				JSON.stringify({
					ok: true,
					data: { target: "/root/Main", actual: false, expected: true, passed: false },
				}),
		};
	});
	try {
		const driver = await connect(9090);
		await assert.rejects(
			driver.assertVisible("/root/Main", { timeoutMs: 50, pollIntervalMs: 10 }),
			(e) =>
				e instanceof DriverError &&
				e.code === "ASSERTION_FAILED" &&
				e.message.includes("/root/Main"),
		);
	} finally {
		m.mock.restore();
	}
});

test("state and dev methods send correct bodies", async () => {
	const { m, calls } = mockFetch({
		"/health": HEALTH_OK,
		"/state": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { values: { hp: 100 } } }),
		},
		"/state/schema": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { properties: [] } }),
		},
		"/state/set": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { updated: ["hp"] } }),
		},
		"/dev/seed": { status: 200, body: JSON.stringify({ ok: true, data: { seeded: true } }) },
		"/dev/time_scale": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { time_scale: 2.0 } }),
		},
		"/dev/pause": { status: 200, body: JSON.stringify({ ok: true, data: { paused: true } }) },
		"/dev/save/load": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { loaded: true } }),
		},
	});
	try {
		const driver = await connect(9090);
		await driver.getState();
		await driver.getSchema();
		await driver.setState({ hp: 150 });
		await driver.setSeed(42);
		await driver.setTimeScale(2.0);
		await driver.setPause(true);
		await driver.loadSaveSlot("save1");

		assert.equal(calls.length, 8);
		assert.equal(JSON.parse(calls[3].init.body).values.hp, 150);
		assert.equal(JSON.parse(calls[4].init.body).seed, 42);
		assert.equal(JSON.parse(calls[5].init.body).scale, 2.0);
		assert.equal(JSON.parse(calls[6].init.body).enabled, true);
		assert.equal(JSON.parse(calls[7].init.body).slot, "save1");
	} finally {
		m.mock.restore();
	}
});

test("test_id: prefix syntax and loadScene path normalization", async () => {
	const { m, calls } = mockFetch({
		"/health": HEALTH_OK,
		"/input/click": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { injected: true } }),
		},
		"/wait/frames": { status: 200, body: JSON.stringify({ ok: true, data: { frames: 1 } }) },
		"/scene/load": {
			status: 200,
			body: JSON.stringify({
				ok: true,
				data: { loaded: "res://scenes/main.tscn", scene_ready: true },
			}),
		},
	});
	try {
		const driver = await connect(9090);
		await driver.click("test_id:btn_submit");
		await driver.loadScene("scenes/main.tscn");

		// Click call: calls[1] is /input/click, calls[2] is /wait/frames
		assert.equal(JSON.parse(calls[1].init.body).test_id, "btn_submit");
		// loadScene call: calls[3] is /scene/load with normalized res:// path
		assert.equal(JSON.parse(calls[3].init.body).path, "res://scenes/main.tscn");
	} finally {
		m.mock.restore();
	}
});

test("reset, loadScene with tweenMode, assertText, and waitTween", async () => {
	const { m, calls } = mockFetch({
		"/health": HEALTH_OK,
		"/reset": {
			status: 200,
			body: JSON.stringify({
				ok: true,
				data: { reloaded_scene: "res://Main.tscn", scene_ready: true },
			}),
		},
		"/scene/load": {
			status: 200,
			body: JSON.stringify({
				ok: true,
				data: { loaded: "res://Level.tscn", scene_ready: true },
			}),
		},
		"/assert/property": {
			status: 200,
			body: JSON.stringify({
				ok: true,
				data: {
					target: "/root/Label",
					property: "text",
					actual: "Score: 10",
					expected: "Score: 10",
					passed: true,
				},
			}),
		},
		"/wait/tween": {
			status: 200,
			body: JSON.stringify({ ok: true, data: { tweens_remaining: 0 } }),
		},
	});
	try {
		const driver = await connect(9090);
		const resetRes = await driver.reset({ tweenMode: "await" });
		assert.equal(resetRes.reloaded_scene, "res://Main.tscn");
		assert.equal(JSON.parse(calls[1].init.body).tween_mode, "await");

		await driver.loadScene("res://Level.tscn", { tweenMode: "kill" });
		assert.equal(JSON.parse(calls[2].init.body).tween_mode, "kill");

		const textRes = await driver.assertText("/root/Label", "Score: 10");
		assert.equal(textRes.passed, true);
		assert.equal(JSON.parse(calls[3].init.body).property, "text");
		assert.equal(JSON.parse(calls[3].init.body).expected, "Score: 10");

		const tweenRes = await driver.waitTween({ timeout: 3000 });
		assert.equal(tweenRes.tweens_remaining, 0);
		assert.equal(JSON.parse(calls[4].init.body).timeout, 3000);
	} finally {
		m.mock.restore();
	}
});

test("screenshot with base64 and binary format", async () => {
	const fakePng = Buffer.from("fake_png_data");
	const { m } = mockFetch({
		"/health": HEALTH_OK,
		"/screenshot/capture": {
			status: 200,
			contentType: "image/png",
			headers: { "x-image-width": "1280", "x-image-height": "720" },
			rawBuffer: fakePng,
		},
	});
	try {
		const driver = await connect(9090);
		const binaryRes = await driver.screenshot();
		assert.ok(binaryRes.buffer);
		assert.equal(Buffer.from(binaryRes.buffer).toString(), "fake_png_data");
		assert.equal(binaryRes.width, 1280);
		assert.equal(binaryRes.height, 720);
		assert.equal(binaryRes.contentType, "image/png");
	} finally {
		m.mock.restore();
	}

	const { m: m2 } = mockFetch({
		"/health": HEALTH_OK,
		"/screenshot/capture": {
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				ok: true,
				data: { image: "base64str", width: 800, height: 600, format: "png" },
			}),
		},
	});
	try {
		const driver = await connect(9090);
		const base64Res = await driver.screenshot({ format: "base64" });
		assert.equal(base64Res.image, "base64str");
		assert.equal(base64Res.width, 800);
		assert.equal(base64Res.height, 600);
	} finally {
		m2.mock.restore();
	}
});

test("screenshotRegion with test_id and explicit rect", async () => {
	const { m, calls } = mockFetch({
		"/health": HEALTH_OK,
		"/screenshot/region": {
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				ok: true,
				data: { image: "region_base64", width: 100, height: 50, format: "png" },
			}),
		},
	});
	try {
		const driver = await connect(9090);
		const res = await driver.screenshotRegion("test_id:my_button", {
			format: "base64",
			rect: { x: 10, y: 10, w: 100, h: 50 },
		});
		assert.equal(res.image, "region_base64");
		const sentBody = JSON.parse(calls[1].init.body);
		assert.equal(sentBody.test_id, "my_button");
		assert.deepEqual(sentBody.rect, { x: 10, y: 10, w: 100, h: 50 });
	} finally {
		m.mock.restore();
	}
});

test("screenshot handles HEADLESS_RENDERING_DISABLED and HDR_NOT_SUPPORTED errors", async () => {
	const { m } = mockFetch({
		"/health": HEALTH_OK,
		"/screenshot/capture": {
			status: 400,
			contentType: "application/json",
			body: JSON.stringify({
				ok: false,
				error: {
					code: "HEADLESS_RENDERING_DISABLED",
					message: "cannot capture screenshot in headless mode",
				},
			}),
		},
	});
	try {
		const driver = await connect(9090);
		await assert.rejects(
			driver.screenshot(),
			(e) =>
				e instanceof DriverError &&
				e.code === "HEADLESS_RENDERING_DISABLED" &&
				e.status === 400,
		);
	} finally {
		m.mock.restore();
	}

	const { m: m2 } = mockFetch({
		"/health": HEALTH_OK,
		"/screenshot/capture": {
			status: 400,
			contentType: "application/json",
			body: JSON.stringify({
				ok: false,
				error: { code: "HDR_NOT_SUPPORTED", message: "HDR not supported" },
			}),
		},
	});
	try {
		const driver = await connect(9090);
		await assert.rejects(
			driver.screenshot({ hdr: true }),
			(e) => e instanceof DriverError && e.code === "HDR_NOT_SUPPORTED" && e.status === 400,
		);
	} finally {
		m2.mock.restore();
	}
});
