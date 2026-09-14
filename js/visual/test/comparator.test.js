import { test } from "node:test";
import assert from "node:assert/strict";
import { compare, solidPng, SizeMismatchError } from "../src/comparator.js";
import sharp from "sharp";

/** Build a PNG with a single pixel changed from a base solid color. */
async function withPixelDelta(basePng, x, y, color) {
	const img = sharp(basePng);
	const { width, height } = await img.metadata();
	const overlay = await sharp({
		create: { width, height, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
	})
		.composite([])
		.png()
		.toBuffer();
	void overlay;
	// Simpler: composite a 1x1 rect at (x, y).
	const patch = await sharp({
		create: { width: 1, height: 1, channels: 4, background: color },
	})
		.png()
		.toBuffer();
	return img
		.composite([{ input: patch, left: x, top: y }])
		.png()
		.toBuffer();
}

test("identical buffers match with zero diff pixels", async () => {
	const png = await solidPng(64, 32, "#336699");
	const r = await compare(png, png);
	assert.equal(r.match, true);
	assert.equal(r.diffPixels, 0);
	assert.equal(r.totalPixels, 64 * 32);
	assert.equal(r.ratio, 0);
	assert.ok(Buffer.isBuffer(r.diffPng));
});

test("single pixel delta detected at default threshold", async () => {
	const base = await solidPng(64, 32, "#336699");
	const actual = await withPixelDelta(base, 10, 10, { r: 255, g: 0, b: 0, alpha: 1 });
	const r = await compare(actual, base);
	assert.equal(r.match, false);
	assert.ok(r.diffPixels >= 1, `expected diff pixels, got ${r.diffPixels}`);
	assert.ok(r.diffPng.length > 0);
});

test("high threshold tolerates the delta", async () => {
	const base = await solidPng(64, 32, "#336699");
	// One-channel delta of 1/255 (~0.004): tolerated at threshold 0.5.
	const actual = await withPixelDelta(base, 10, 10, { r: 51, g: 102, b: 154, alpha: 1 });
	const r = await compare(actual, base, { threshold: 0.5 });
	assert.equal(r.match, true);
});

test("zero threshold flags any channel delta", async () => {
	const base = await solidPng(32, 32, "#000000");
	const actual = await withPixelDelta(base, 5, 5, { r: 1, g: 0, b: 0, alpha: 1 });
	const r = await compare(actual, base, { threshold: 0 });
	assert.equal(r.match, false);
});

test("ROI restricts comparison: difference outside ROI passes", async () => {
	const base = await solidPng(64, 64, "#336699");
	const actual = await withPixelDelta(base, 50, 50, { r: 255, g: 0, b: 0, alpha: 1 });
	const r = await compare(actual, base, { roi: { x: 0, y: 0, w: 32, h: 32 } });
	assert.equal(r.match, true);
	assert.equal(r.totalPixels, 32 * 32);
});

test("ROI inside: difference inside ROI fails", async () => {
	const base = await solidPng(64, 64, "#336699");
	const actual = await withPixelDelta(base, 10, 10, { r: 255, g: 0, b: 0, alpha: 1 });
	const r = await compare(actual, base, { roi: { x: 0, y: 0, w: 32, h: 32 } });
	assert.equal(r.match, false);
});

test("exclusion rect zeroes the region", async () => {
	const base = await solidPng(64, 64, "#336699");
	const actual = await withPixelDelta(base, 10, 10, { r: 255, g: 0, b: 0, alpha: 1 });
	const r = await compare(actual, base, {
		exclude: { rects: [{ x: 5, y: 5, w: 10, h: 10 }] },
	});
	assert.equal(r.match, true);
});

test("exclusion testIdRects behaves like rects", async () => {
	const base = await solidPng(64, 64, "#336699");
	const actual = await withPixelDelta(base, 10, 10, { r: 255, g: 0, b: 0, alpha: 1 });
	const r = await compare(actual, base, {
		exclude: { testIdRects: [{ x: 5, y: 5, w: 10, h: 10 }] },
	});
	assert.equal(r.match, true);
});

test("size mismatch throws SizeMismatchError with dimensions", async () => {
	const a = await solidPng(64, 32, "#336699");
	const b = await solidPng(32, 32, "#336699");
	await assert.rejects(
		() => compare(a, b),
		/** @param {Error} err */
		(err) => {
			assert.equal(err.name, "SizeMismatchError");
			assert.match(err.message, /actual 64x32 vs baseline 32x32/);
			return true;
		},
	);
});

test("allowResize auto-resizes the baseline", async () => {
	const a = await solidPng(64, 32, "#336699");
	const b = await solidPng(32, 16, "#336699");
	const r = await compare(a, b, { allowResize: true });
	assert.equal(r.match, true);
	assert.equal(r.size.width, 64);
});

test("invalid PNG throws InvalidImageError", async () => {
	const base = await solidPng(8, 8, "#000000");
	await assert.rejects(
		() => compare(Buffer.from("not a png"), base),
		/** @param {Error} err */
		(err) => err.name === "InvalidImageError",
	);
});
