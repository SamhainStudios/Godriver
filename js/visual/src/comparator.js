/**
 * Visual comparator for Godriver visual regression (GTD-051).
 *
 * Compares two PNG buffers with pixelmatch, supporting region-of-interest
 * restriction and exclusion masks (rects or test_id-resolved rects).
 * Pure functions, no I/O beyond PNG decode/encode.
 */
import pixelmatch from "pixelmatch";
import { PNG } from "pngjs";
import sharp from "sharp";

/** Error thrown when the two images have different dimensions. */
export class SizeMismatchError extends Error {
	/**
	 * @param {{ width: number, height: number }} actual
	 * @param {{ width: number, height: number }} baseline
	 */
	constructor(actual, baseline) {
		super(
			`image size mismatch: actual ${actual.width}x${actual.height} vs baseline ${baseline.width}x${baseline.height} ` +
				"(capture viewport/region must match the baseline; use allowResize to auto-resize)",
		);
		this.name = "SizeMismatchError";
		this.actual = actual;
		this.baseline = baseline;
	}
}

/** Error thrown when a PNG buffer cannot be decoded. */
export class InvalidImageError extends Error {
	/** @param {string} which */
	constructor(which) {
		super(`invalid PNG data in ${which}`);
		this.name = "InvalidImageError";
	}
}

/**
 * @typedef {Object} Rect
 * @property {number} x
 * @property {number} y
 * @property {number} w
 * @property {number} h
 */

/**
 * @typedef {Object} CompareOptions
 * @property {number} [threshold] pixelmatch color threshold, 0..1 (default 0.01 = 1%)
 * @property {boolean} [includeAA] include anti-aliased pixels in the diff (default false)
 * @property {Rect} [roi] restrict comparison to this region
 * @property {{ rects?: Rect[], testIdRects?: Rect[] }} [exclude] regions zeroed in both images before diffing
 * @property {boolean} [allowResize] auto-resize the baseline to the actual size (default false)
 */

/**
 * @typedef {Object} CompareResult
 * @property {boolean} match true when diffPixels === 0
 * @property {number} diffPixels count of differing pixels inside the compared region
 * @property {number} totalPixels pixels inside the compared region
 * @property {number} ratio diffPixels / totalPixels
 * @property {Buffer} diffPng PNG buffer highlighting differences (yellow = diff, green = AA)
 * @property {{ width: number, height: number }} size
 */

/**
 * Decode a PNG buffer into a PNG instance + raw RGBA.
 * @param {Buffer} png
 * @param {string} which label for error messages
 * @returns {Promise<PNG>}
 */
async function decode(png, which) {
	try {
		return PNG.sync.read(png);
	} catch {
		// pngjs can be strict; fall back to sharp re-encode for odd PNGs.
		try {
			const reencoded = await sharp(png).png().toBuffer();
			return PNG.sync.read(reencoded);
		} catch {
			throw new InvalidImageError(which);
		}
	}
}

/** @param {Rect} r @param {number} w @param {number} h @returns {Rect} clamped to image bounds */
function clampRect(r, w, h) {
	const x = Math.max(0, Math.min(r.x, w));
	const y = Math.max(0, Math.min(r.y, h));
	return {
		x,
		y,
		w: Math.max(0, Math.min(r.w, w - x)),
		h: Math.max(0, Math.min(r.h, h - y)),
	};
}

/**
 * Zero the RGBA of all pixels inside rect (in place).
 * @param {PNG} img
 * @param {Rect} rect
 */
function zeroRect(img, rect) {
	for (let y = rect.y; y < rect.y + rect.h; y++) {
		for (let x = rect.x; x < rect.x + rect.w; x++) {
			const idx = (y * img.width + x) * 4;
			img.data[idx] = 0;
			img.data[idx + 1] = 0;
			img.data[idx + 2] = 0;
			img.data[idx + 3] = 255;
		}
	}
}

/**
 * Compare a captured screenshot against a baseline image.
 *
 * @param {Buffer} actualPng captured screenshot (raw PNG bytes from driver.screenshot())
 * @param {Buffer} baselinePng stored baseline PNG
 * @param {CompareOptions} [options]
 * @returns {Promise<CompareResult>}
 */
export async function compare(actualPng, baselinePng, options = {}) {
	const threshold = options.threshold ?? 0.01;
	const includeAA = options.includeAA ?? false;

	let actual = await decode(actualPng, "actual");
	let baseline = await decode(baselinePng, "baseline");

	if (actual.width !== baseline.width || actual.height !== baseline.height) {
		if (options.allowResize) {
			const resized = await sharp(baselinePng)
				.resize(actual.width, actual.height)
				.png()
				.toBuffer();
			baseline = await decode(resized, "baseline");
		} else {
			throw new SizeMismatchError(
				{ width: actual.width, height: actual.height },
				{ width: baseline.width, height: baseline.height },
			);
		}
	}

	// Exclusion masks: zero excluded pixels in BOTH images so they compare equal.
	const masks = [...(options.exclude?.rects ?? []), ...(options.exclude?.testIdRects ?? [])];
	for (const raw of masks) {
		const r = clampRect(raw, actual.width, actual.height);
		zeroRect(actual, r);
		zeroRect(baseline, r);
	}

	// ROI: crop both images to the region before diffing.
	if (options.roi) {
		const r = clampRect(options.roi, actual.width, actual.height);
		actual = cropPng(actual, r);
		baseline = cropPng(baseline, r);
	}

	const diff = new PNG({ width: actual.width, height: actual.height });
	const diffPixels = pixelmatch(
		actual.data,
		baseline.data,
		diff.data,
		actual.width,
		actual.height,
		{ threshold, includeAA },
	);
	const totalPixels = actual.width * actual.height;
	const diffPng = PNG.sync.write(diff);

	return {
		match: diffPixels === 0,
		diffPixels,
		totalPixels,
		ratio: totalPixels > 0 ? diffPixels / totalPixels : 0,
		diffPng,
		size: { width: actual.width, height: actual.height },
	};
}

/**
 * Crop a PNG instance to a rect, returning a new PNG.
 * @param {PNG} img
 * @param {Rect} rect
 * @returns {PNG}
 */
function cropPng(img, rect) {
	const out = new PNG({ width: rect.w, height: rect.h });
	for (let y = 0; y < rect.h; y++) {
		const srcStart = ((y + rect.y) * img.width + rect.x) * 4;
		const dstStart = y * rect.w * 4;
		Buffer.from(img.data.buffer, srcStart, rect.w * 4).copy(out.data, dstStart);
	}
	return out;
}

/**
 * Build a solid-color PNG fixture (test helper, also useful for baselines).
 * @param {number} width
 * @param {number} height
 * @param {string} color CSS color, e.g. "#ff0000"
 * @returns {Promise<Buffer>} PNG buffer
 */
export async function solidPng(width, height, color) {
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="${color}"/></svg>`;
	return sharp(Buffer.from(svg)).png().toBuffer();
}
