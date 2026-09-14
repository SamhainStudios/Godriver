/**
 * Type-test file — compiled by `tsc --noEmit` in CI (GTD-051 acceptance).
 * Asserts the JSDoc-inferred surface of @godriver/visual; contains no runtime code.
 */
import {
	compare,
	solidPng,
	SizeMismatchError,
	InvalidImageError,
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

export { use, png, handle, isInvalid };
