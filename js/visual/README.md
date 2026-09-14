# @godriver/visual

Pixel-comparison engine for Godriver visual regression (GTD-051). Compares two
PNG buffers with [pixelmatch](https://github.com/gljivar/pixelmatch), with
region-of-interest restriction and exclusion masks. Zero test-runner
dependencies.

```sh
npm install @godriver/visual
```

## Usage

```js
import { compare } from "@godriver/visual";

const shot = await driver.screenshot(); // raw PNG bytes (Buffer/Uint8Array)
const baseline = fs.readFileSync("tests/baselines/menu.png");

const result = await compare(Buffer.from(shot.buffer), baseline, {
	threshold: 0.01, // pixelmatch color threshold (0..1)
	includeAA: false, // count anti-aliased pixels
	// roi: { x: 0, y: 0, w: 400, h: 300 },          // restrict comparison
	// exclude: { rects: [{ x: 10, y: 10, w: 50, h: 20 }] }, // zeroed in both
	// allowResize: true,                            // resize baseline to actual
});

if (!result.match) {
	fs.writeFileSync("diff.png", result.diffPng);
	console.log(`${result.diffPixels}/${result.totalPixels} pixels differ`);
}
```

## API

### `compare(actualPng, baselinePng, options?) → Promise<CompareResult>`

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `threshold` | `number` | `0.01` | pixelmatch color threshold (0 = exact) |
| `includeAA` | `boolean` | `false` | include anti-aliased pixels in the diff |
| `roi` | `Rect` | — | restrict comparison to this region |
| `exclude` | `{ rects?: Rect[], testIdRects?: Rect[] }` | — | regions zeroed in **both** images before diffing |
| `allowResize` | `boolean` | `false` | auto-resize the baseline to the actual size |

`Rect` is `{ x, y, w, h }`. Result: `{ match, diffPixels, totalPixels, ratio, diffPng, size }` —
`match` is true only when `diffPixels === 0`; `diffPng` highlights differences
(yellow = diff, green = anti-aliasing).

Throws:

- `SizeMismatchError` — dimensions differ and `allowResize` is not set. Carries
  `actual` / `baseline` `{ width, height }`.
- `InvalidImageError` — a buffer is not decodable as PNG.

### `solidPng(width, height, color) → Promise<Buffer>`

Test helper: builds a solid-color PNG via sharp (useful for fixtures and
synthetic baselines).

## Notes

- Driver parity matters: capture baselines and CI screenshots with the same
  rendering driver (Vulkan vs llvmpipe produce pixel differences). See
  `docs/guides/visual-regression.md` for the full workflow (GTD-052).
- Exclusion masks are applied to both images, so excluded regions never
  contribute to the diff.
