/**
 * Type-test file — compiled by `tsc --noEmit` in CI (GTD-051 acceptance).
 * Asserts the JSDoc-inferred surface of @godriver/visual; contains no runtime code.
 */
import {
	compare,
	solidPng,
	SizeMismatchError,
	InvalidImageError,
	BaselineStore,
	assertMatchesBaseline,
	BaselineMissingError,
	BaselineMismatchError,
} from "../src/index.js";

/** @type {import("../src/comparator.js").CompareResult} */
let typedResult;

// compare signature
async function use(actual: Buffer, baseline: Buffer): Promise<void> {
	const r: Promise<import("../src/comparator.js").CompareResult> = compare(actual, baseline);
	const r2: Promise<import("../src/comparator.js").CompareResult> = compare(actual, baseline, {
		threshold: 0.05,
		includeAA: true,
		allowResize: true,
		roi: { x: 0, y: 0, w: 32, h: 32 },
		exclude: {
			rects: [{ x: 1, y: 1, w: 4, h: 4 }],
			testIdRects: [{ x: 2, y: 2, w: 8, h: 8 }],
		},
	});

	const res: import("../src/comparator.js").CompareResult = await r2;
	const m: boolean = res.match;
	const diff: Buffer = res.diffPng;
	const n: number = res.diffPixels;
	const total: number = res.totalPixels;
	const ratio: number = res.ratio;
	const size: { width: number; height: number } = res.size;
	console.log(m, diff, n, total, ratio, size);
}

// helpers + error classes
const png: Promise<Buffer> = solidPng(32, 32, "#336699");

function handle(e: SizeMismatchError): string {
	const aw: number = e.actual.width;
	const bh: number = e.baseline.height;
	return `${aw} vs ${bh}`;
}

function isInvalid(e: InvalidImageError): boolean {
	return e.name === "InvalidImageError";
}

// GTD-052: baseline workflow surface
async function baselineFlow(driver: { screenshot: (opts?: { format?: "binary" | "base64" }) => Promise<{ buffer: Uint8Array; width: number; height: number; contentType: string }> }): Promise<void> {
	const store = new BaselineStore({ dir: "tests/baselines", artifactsDir: "artifacts/visual" });
	const pngPath: string = store.pngPath("menu");
	const metaPath: string = store.metaPath("menu");
	const artDir: string = store.artifactDir("menu");
	const exists: Promise<boolean> = store.exists("menu");
	const read: { png: Buffer; meta: import("../src/baselines.js").BaselineMeta | null } = await store.read("menu");
	await store.write("menu", read.png, { driver: "godot-4.7.2", width: 32, height: 32 });

	const result = await assertMatchesBaseline(store, "menu", {
		screenshot: driver.screenshot,
		driverLabel: "godot-4.7.2",
		threshold: 0.02,
		roi: { x: 0, y: 0, w: 32, h: 32 },
	});
	const created: boolean | undefined = result.created;
	const updated: boolean | undefined = result.updated;
	const match: boolean = result.match;
	console.log(pngPath, metaPath, artDir, exists, created, updated, match);

	function missing(e: BaselineMissingError): string {
		return e.path;
	}
	function mismatch(e: BaselineMismatchError): [string, number, number] {
		return [e.reportPath, e.diffPixels, e.ratio];
	}
	console.log(missing, mismatch);
}

export { baselineFlow, isInvalid };
