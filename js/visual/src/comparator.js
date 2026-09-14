/**
 * Visual comparator for Godriver visual regression (GTD-051).
 *
 * Compares two PNG buffers with pixelmatch, supporting region-of-interest
 * restriction and exclusion masks (rects or test_id-resolved rects).
 * Pure functions; PNG decode/encode goes through sharp (GTD-057 removed
 * the unmaintained pngjs dependency).
 */
import pixelmatch from "pixelmatch";
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
 * @typedef {Object} RawImage decoded RGBA pixels
 * @property {Buffer} data RGBA, width*height*4
 * @property {number} width
 * @property {number} height
 */

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
 * Decode a PNG buffer into raw RGBA via sharp.
 * @param {Buffer} png
 * @param {string} which label for error messages
 * @returns {Promise<RawImage>}
 */
async function decode(png, which) {
	try {
		const { data, info } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
		return { data: Buffer.from(data), width: info.width, height: info.height };
	} catch {
		throw new InvalidImageError(which);
	}
}

/**
 * Encode raw RGBA back to PNG.
 * @param {RawImage} img
 * @returns {Promise<Buffer>}
 */
async function encodePng(img) {
	return sharp(img.data, { raw: { width: img.width, height: img.height, channels: 4 } }).png().toBuffer();
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
 * @param {RawImage} img
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
 * Crop a raw image to a rect, returning a new raw image.
 * @param {RawImage} img
 * @param {Rect} rect
 * @returns {RawImage}
 */
function cropRaw(img, rect) {
	const out = Buffer.alloc(rect.w * rect.h * 4);
	for (let y = 0; y < rect.h; y++) {
		const srcStart = ((y + rect.y) * img.width + rect.x) * 4;
		img.data.copy(out, y * rect.w * 4, srcStart, srcStart + rect.w * 4);
	}
	return { data: out, width: rect.w, height: rect.h };
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
				.ensureAlpha()
				.raw()
				.toBuffer();
			baseline = { data: Buffer.from(resized), width: actual.width, height: actual.height };
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
		actual = cropRaw(actual, r);
		baseline = cropRaw(baseline, r);
	}

	const diffData = Buffer.alloc(actual.width * actual.height * 4);
	const diffPixels = pixelmatch(
		actual.data,
		baseline.data,
		diffData,
		actual.width,
		actual.height,
		{ threshold, includeAA },
	);
	const totalPixels = actual.width * actual.height;
	const diffPng = await sharp(diffData, {
		raw: { width: actual.width, height: actual.height, channels: 4 },
	})
		.png()
		.toBuffer();

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
