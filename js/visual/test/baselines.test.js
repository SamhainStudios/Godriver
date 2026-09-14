/**
 * GTD-052 tests: BaselineStore round-trip, assertMatchesBaseline workflow
 * (create / update / match / mismatch artifacts), and report contents.
 * Uses real temp directories, no fs mocks.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	BaselineStore,
	assertMatchesBaseline,
	BaselineMissingError,
	BaselineMismatchError,
	solidPng,
} from "../src/index.js";

async function tempStore() {
	const root = await mkdtemp(join(tmpdir(), "godriver-visual-"));
	return {
		store: new BaselineStore({
			dir: join(root, "baselines"),
			artifactsDir: join(root, "artifacts", "visual"),
		}),
		root,
	};
}

/** Build a screenshot fn returning a fixed PNG. @param {Buffer} png @returns {AssertOptions["screenshot"]} */
function captureFn(png) {
	return async () => ({
		buffer: new Uint8Array(png),
		width: 32,
		height: 32,
		contentType: "image/png",
	});
}

function withEnv(env, fn) {
	/** @type {Record<string, string | undefined>} */
	const prev = {};
	for (const k of Object.keys(env)) {
		prev[k] = process.env[k];
	}
	return async () => {
		for (const [k, v] of Object.entries(env)) {
			process.env[k] = v;
		}
		try {
			await fn();
		} finally {
			for (const k of Object.keys(env)) {
				if (prev[k] === undefined) {
					delete process.env[k];
				} else {
					process.env[k] = prev[k];
				}
			}
		}
	};
}

test("store round-trips png + sidecar metadata", async () => {
	const { store, root } = await tempStore();
	try {
		const png = await solidPng(32, 32, "#336699");
		await store.write("roundtrip", png, { driver: "test", width: 32, height: 32 });
		assert.equal(await store.exists("roundtrip"), true);
		const { png: readPng, meta } = await store.read("roundtrip");
		assert.deepEqual(readPng, png);
		assert.equal(meta?.driver, "test");
		assert.equal(meta?.width, 32);
		assert.ok(typeof meta?.updatedAt === "string");
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("first run without baseline and without UPDATE_BASELINE throws BaselineMissingError with guidance", async () => {
	const { store, root } = await tempStore();
	try {
		const png = await solidPng(32, 32, "#336699");
		await assert.rejects(
			() => assertMatchesBaseline(store, "missing", { screenshot: captureFn(png) }),
			/** @param {Error} err */
			(err) =>
				err instanceof BaselineMissingError && /UPDATE_BASELINE=true/.test(err.message),
		);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test(
	"first run with UPDATE_BASELINE=true writes baseline + sidecar and passes",
	withEnv({ UPDATE_BASELINE: "true" }, async () => {
		const { store, root } = await tempStore();
		try {
			const png = await solidPng(32, 32, "#336699");
			const result = await assertMatchesBaseline(store, "created", {
				screenshot: captureFn(png),
				driverLabel: "godot-4.7.2",
			});
			assert.equal(result.created, true);
			const { meta } = await store.read("created");
			assert.equal(meta?.driver, "godot-4.7.2");
			assert.equal(meta?.width, 32);
		} finally {
			await rm(root, { recursive: true, force: true });
		}
	}),
);

test(
	"UPDATE_BASELINE=true regenerates an existing baseline",
	withEnv({ UPDATE_BASELINE: "true" }, async () => {
		const { store, root } = await tempStore();
		try {
			await store.write("regen", await solidPng(32, 32, "#336699"), { driver: "old" });
			const png = await solidPng(32, 32, "#ff0000");
			const result = await assertMatchesBaseline(store, "regen", {
				screenshot: captureFn(png),
			});
			assert.equal(result.updated, true);
			const { png: stored } = await store.read("regen");
			assert.deepEqual(stored, png);
		} finally {
			await rm(root, { recursive: true, force: true });
		}
	}),
);

test("identical capture passes and writes nothing to artifacts", async () => {
	const { store, root } = await tempStore();
	try {
		const png = await solidPng(32, 32, "#336699");
		await store.write("same", png, {});
		const result = await assertMatchesBaseline(store, "same", { screenshot: captureFn(png) });
		assert.equal(result.match, true);
		await assert.rejects(
			() => readFile(join(store.artifactDir("same"), "actual.png")),
			/ENOENT/,
		);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("injected pixel difference fails with actual/diff/report artifacts", async () => {
	const { store, root } = await tempStore();
	try {
		const baseline = await solidPng(32, 32, "#336699");
		await store.write("broken", baseline, { driver: "test" });
		// Actual differs by one pixel via a sharp composite patch.
		const { default: sharp } = await import("sharp");
		const patch = await sharp({
			create: { width: 1, height: 1, channels: 3, background: "#ff0000" },
		})
			.png()
			.toBuffer();
		const actual = await sharp(baseline)
			.composite([{ input: patch, left: 5, top: 7 }])
			.png()
			.toBuffer();
		await assert.rejects(
			() => assertMatchesBaseline(store, "broken", { screenshot: captureFn(actual) }),
			/** @param {Error} err */
			(err) => err instanceof BaselineMismatchError && err.diffPixels > 0,
		);
		const report = await readFile(join(store.artifactDir("broken"), "report.html"), "utf8");
		assert.ok(report.includes("data:image/png;base64,"), "report embeds images");
		assert.ok(
			(report.match(/data:image\/png;base64,/g) ?? []).length >= 3,
			"report embeds all three images",
		);
		assert.ok(report.includes("MISMATCH"));
		await readFile(join(store.artifactDir("broken"), "actual.png"));
		await readFile(join(store.artifactDir("broken"), "diff.png"));
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test(
	"GODRIVER_DIFF_OUTPUT=1 writes diff artifacts even on success",
	withEnv({ GODRIVER_DIFF_OUTPUT: "1" }, async () => {
		const { store, root } = await tempStore();
		try {
			const png = await solidPng(32, 32, "#336699");
			await store.write("debug", png, {});
			const result = await assertMatchesBaseline(store, "debug", {
				screenshot: captureFn(png),
			});
			assert.equal(result.match, true);
			await readFile(join(store.artifactDir("debug"), "diff.png"));
		} finally {
			await rm(root, { recursive: true, force: true });
		}
	}),
);
