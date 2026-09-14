/**
 * HTML diff report builder for Godriver visual regression (GTD-052).
 *
 * Builds a self-contained HTML report with baseline/actual/diff images
 * inlined as base64 data URIs plus a metadata table.
 */

/**
 * @typedef {Object} ReportInput
 * @property {string} name baseline name
 * @property {Buffer} baselinePng
 * @property {Buffer} actualPng
 * @property {Buffer} diffPng
 * @property {Record<string, unknown>} [baselineMeta] sidecar metadata of the baseline
 * @property {{ diffPixels: number, totalPixels: number, ratio: number, size: { width: number, height: number } }} result comparator result
 */

/**
 * Encode a PNG buffer as a base64 data URI.
 * @param {Buffer} png
 * @returns {string}
 */
function dataUri(png) {
	return `data:image/png;base64,${png.toString("base64")}`;
}

/**
 * Escape a string for safe HTML text interpolation.
 * @param {unknown} value
 * @returns {string}
 */
function esc(value) {
	return String(value)
		.replaceAll("&", "&amp;")
		.replaceAll("<", "&lt;")
		.replaceAll(">", "&gt;")
		.replaceAll('"', "&quot;");
}

/**
 * Build the HTML diff report.
 *
 * @param {ReportInput} input
 * @returns {string} self-contained HTML document
 */
export function buildReport(input) {
	const { name, baselinePng, actualPng, diffPng, baselineMeta = {}, result } = input;
	const metaRows = Object.entries(baselineMeta)
		.map(([k, v]) => `<tr><th>${esc(k)}</th><td>${esc(typeof v === "object" ? JSON.stringify(v) : v)}</td></tr>`)
		.join("\n");
	const pct = (result.totalPixels > 0 ? result.ratio * 100 : 0).toFixed(4);
	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Godriver visual diff: ${esc(name)}</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 1.5rem; background: #111; color: #eee; }
  h1 { font-size: 1.2rem; }
  table { border-collapse: collapse; margin: 1rem 0; }
  th, td { border: 1px solid #444; padding: 0.25rem 0.6rem; text-align: left; font-size: 0.85rem; }
  th { background: #222; }
  .images { display: flex; flex-wrap: wrap; gap: 1rem; }
  figure { margin: 0; }
  figcaption { font-size: 0.8rem; color: #aaa; margin-bottom: 0.25rem; }
  img { max-width: 45vw; border: 1px solid #444; image-rendering: pixelated; }
  .fail { color: #ff6b6b; font-weight: bold; }
</style>
</head>
<body>
<h1>Visual diff: ${esc(name)}</h1>
<p class="fail">MISMATCH: ${result.diffPixels} differing pixels of ${result.totalPixels} (${pct}%) at ${result.size.width}x${result.size.height}</p>
<table>
${metaRows}
</table>
<div class="images">
<figure><figcaption>Baseline</figcaption><img alt="baseline" src="${dataUri(baselinePng)}"></figure>
<figure><figcaption>Actual</figcaption><img alt="actual" src="${dataUri(actualPng)}"></figure>
<figure><figcaption>Diff (yellow = differing, green = anti-aliasing)</figcaption><img alt="diff" src="${dataUri(diffPng)}"></figure>
</div>
</body>
</html>
`;
}
