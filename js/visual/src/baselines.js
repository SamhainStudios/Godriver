/**
 * Baseline storage and assertion workflow for Godriver visual regression (GTD-052).
 *
 * File-based baselines under a configurable directory (default `tests/baselines/`),
 * `UPDATE_BASELINE=true` regeneration, and `assertMatchesBaseline()` which
 * captures via the driver, compares with the GTD-051 comparator, and writes a
 * self-contained HTML diff report on mismatch.
 */
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { compare } from "./comparator.js";
import { buildReport } from "./report.js";

/** Thrown when no baseline exists for the requested name. */
export class BaselineMissingError extends Error {
	/** @param {string} path expected baseline file path */
	constructor(path) {
		super(
			`no baseline at ${path}. Capture one first with UPDATE_BASELINE=true (or the BaselineStore.write API).`,
		);
		this.name = "BaselineMissingError";
		this.path = path;
	}
}

/** Thrown when the capture differs from the baseline beyond the threshold. */
export class BaselineMismatchError extends Error {
	/**
	 * @param {string} name baseline name
	 * @param {string} reportPath written report.html path
	 * @param {{ diffPixels: number, totalPixels: number, ratio: number }} result
	 */
	constructor(name, reportPath, result) {
		const pct = (result.totalPixels > 0 ? result.ratio * 100 : 0).toFixed(4);
		super(
			`visual mismatch for "${name}": ${result.diffPixels} differing pixels (${pct}%). Report: ${reportPath}`,
		);
		this.name = "BaselineMismatchError";
		this.baselineName = name;
		this.reportPath = reportPath;
		this.diffPixels = result.diffPixels;
		this.totalPixels = result.totalPixels;
		this.ratio = result.ratio;
	}
}

/**
 * @typedef {Object} BaselineMeta
 * @property {string} [driver] driver/runtime identifier recorded with the baseline
 * @property {number} [width] capture width
 * @property {number} [height] capture height
 * @property {import("./comparator.js").Rect} [roi] region of interest used
 * @property {import("./comparator.js").CompareOptions["exclude"]} [exclude] exclusion masks used
 * @property {string} [updatedAt] ISO timestamp of the last write
 */

/**
 * File-based baseline store: `<dir>/<name>.png` + `<dir>/<name>.json` sidecar.
 */
export class BaselineStore {
	/**
	 * @param {{ dir?: string, artifactsDir?: string }} [options]
	 *        dir: baseline directory (default "tests/baselines")
	 *        artifactsDir: mismatch artifact root (default "artifacts/visual")
	 */
	constructor(options = {}) {
		/** @type {string} */
		this.dir = options.dir ?? "tests/baselines";
		/** @type {string} */
		this.artifactsDir = options.artifactsDir ?? "artifacts/visual";
	}

	/** @param {string} name @returns {string} path of the baseline PNG */
	pngPath(name) {
		return join(this.dir, `${name}.png`);
	}

	/** @param {string} name @returns {string} path of the sidecar JSON */
	metaPath(name) {
		return join(this.dir, `${name}.json`);
	}

	/** @param {string} name @returns {string} artifact directory for this baseline */
	artifactDir(name) {
		return join(this.artifactsDir, name);
	}

	/**
	 * @param {string} name
	 * @returns {Promise<boolean>} true when the baseline PNG exists
	 */
	async exists(name) {
		return readFile(this.pngPath(name))
			.then(() => true)
			.catch(() => false);
	}

	/**
	 * Read a baseline and its sidecar metadata.
	 *
	 * @param {string} name
	 * @returns {Promise<{ png: Buffer, meta: BaselineMeta | null }>} meta is null when no sidecar exists
	 */
	async read(name) {
		const png = await readFile(this.pngPath(name));
		let meta = null;
		try {
			meta = /** @type {BaselineMeta} */ (
				JSON.parse(await readFile(this.metaPath(name), "utf8"))
			);
		} catch {
			// sidecar optional
		}
		return { png, meta };
	}

	/**
	 * Write a baseline PNG + sidecar metadata.
	 *
	 * @param {string} name
	 * @param {Buffer} png
	 * @param {BaselineMeta} [meta] fields merged with updatedAt
	 * @returns {Promise<void>}
	 */
	async write(name, png, meta = {}) {
		await mkdir(dirname(this.pngPath(name)), { recursive: true });
		await writeFile(this.pngPath(name), png);
		const sidecar = { ...meta, updatedAt: new Date().toISOString() };
		await writeFile(this.metaPath(name), `${JSON.stringify(sidecar, null, "\t")}\n`);
	}
}

/**
 * @typedef {Object} AssertOptions
 * @property {number} [threshold] pixelmatch threshold (default 0.01)
 * @property {boolean} [includeAA] include anti-aliased pixels (default false)
 * @property {import("./comparator.js").Rect} [roi] restrict comparison to this region
 * @property {import("./comparator.js").CompareOptions["exclude"]} [exclude] exclusion masks
 * @property {boolean} [allowResize] auto-resize baseline to actual size (default false)
 * @property {string} [driverLabel] recorded in the sidecar when writing baselines
 * @property {(opts?: { format?: "binary" | "base64" }) => Promise<{ buffer: Uint8Array, width: number, height: number, contentType: string }>} screenshot
 *        capture function (pass `driver.screenshot.bind(driver)`); must return raw PNG bytes
 */

/**
 * Capture via the driver and assert it matches the stored baseline.
 *
 * Behavior matrix:
 * - no baseline + UPDATE_BASELINE=true: writes baseline + sidecar, passes ({created: true})
 * - no baseline otherwise: throws BaselineMissingError with guidance
 * - baseline + UPDATE_BASELINE=true: regenerates baseline + sidecar, passes ({updated: true})
 * - baseline + match: passes; writes diff PNG to artifacts only when GODRIVER_DIFF_OUTPUT=1
 * - baseline + mismatch: writes actual.png, diff.png, report.html under
 *   artifacts/visual/<name>/ and throws BaselineMismatchError
 *
 * @param {BaselineStore} store
 * @param {string} name baseline name
 * @param {AssertOptions} options capture + compare options
 * @returns {Promise<{ match: boolean, created?: boolean, updated?: boolean, diffPixels?: number, totalPixels?: number, ratio?: number }>}
 */
export async function assertMatchesBaseline(store, name, options) {
	const capture = await options.screenshot({ format: "binary" });
	const actualPng = Buffer.from(capture.buffer);
	const meta = {
		driver: options.driverLabel ?? "",
		width: capture.width,
		height: capture.height,
		roi: options.roi,
		exclude: options.exclude,
	};

	if (!(await store.exists(name))) {
		if (process.env.UPDATE_BASELINE === "true") {
			await store.write(name, actualPng, meta);
			return { match: true, created: true };
		}
		throw new BaselineMissingError(store.pngPath(name));
	}

	if (process.env.UPDATE_BASELINE === "true") {
		await store.write(name, actualPng, meta);
		return { match: true, updated: true };
	}

	const { png: baselinePng, meta: baselineMeta } = await store.read(name);
	const result = await compare(actualPng, baselinePng, {
		threshold: options.threshold,
		includeAA: options.includeAA,
		roi: options.roi,
		exclude: options.exclude,
		allowResize: options.allowResize,
	});

	if (result.match) {
		if (process.env.GODRIVER_DIFF_OUTPUT === "1") {
			await writeArtifacts(store, name, {
				actualPng,
				baselinePng,
				diffPng: result.diffPng,
				baselineMeta,
				result,
			});
		}
		return {
			match: true,
			diffPixels: result.diffPixels,
			totalPixels: result.totalPixels,
			ratio: result.ratio,
		};
	}

	const paths = await writeArtifacts(store, name, {
		actualPng,
		baselinePng,
		diffPng: result.diffPng,
		baselineMeta,
		result,
	});
	throw new BaselineMismatchError(name, paths.report, result);
}

/**
 * Write mismatch (or debug) artifacts: actual.png, diff.png, report.html.
 *
 * @param {BaselineStore} store
 * @param {string} name
 * @param {{ actualPng: Buffer, baselinePng: Buffer, diffPng: Buffer, baselineMeta: BaselineMeta | null, result: { diffPixels: number, totalPixels: number, ratio: number, size: { width: number, height: number } } }} parts
 * @returns {Promise<{ dir: string, actual: string, diff: string, report: string }>} written paths
 */
async function writeArtifacts(store, name, parts) {
	const dir = store.artifactDir(name);
	await mkdir(dir, { recursive: true });
	const actual = join(dir, "actual.png");
	const diff = join(dir, "diff.png");
	const report = join(dir, "report.html");
	await writeFile(actual, parts.actualPng);
	await writeFile(diff, parts.diffPng);
	await writeFile(
		report,
		buildReport({
			name,
			baselinePng: parts.baselinePng,
			actualPng: parts.actualPng,
			diffPng: parts.diffPng,
			baselineMeta: parts.baselineMeta ?? {},
			result: parts.result,
		}),
	);
	return { dir, actual, diff, report };
}
