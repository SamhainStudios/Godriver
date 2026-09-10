# Vendored: gdUnit4

- **Upstream:** https://github.com/MikeSchulze/gdUnit4
- **Pinned version:** v6.2.1 (tag)
- **License:** MIT (see `LICENSE` in this directory)
- **Vendored at:** 2026-09 (GTD-007 self-test scaffold)

## Why this version

- v6.2.1 is the current stable release and **works on Godot 4.7.2** (project base version): unit suites run green headless (12/12, exit 0).
- v6.2.1 does **NOT compile on Godot 4.4** (GDScript parse errors in `GdUnitTestCIRunner.gd` — v6.x requires newer type inference). If the project must ever run on 4.4 again, fall back to **v5.1.1** (tag, commit `c924c7a`), which declares 4.3/4.4/4.4.1 support. A backup of the v5.1.1 tree was kept outside the repo during the swap.

## Usage (headless)

```
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add scratch/spike/test --ignoreHeadlessMode
```

- `--ignoreHeadlessMode` is REQUIRED for headless runs (the CLI refuses headless by default, exit 103).
- Exit codes: 0 = green, 100 = test failures, 103 = headless refusal.
- Reports land in `reports/report_N/` (gitignored).

## Deviations from upstream

None. The tree is unmodified upstream v6.2.1.

## Update procedure

1. Clone upstream at the target tag, diff against this directory.
2. Re-run the unit suites headless (command above) on the project's base Godot version.
3. Update this file (version, date, deviations).
4. Review cadence: every 2 Godot minor versions, or immediately for security fixes (≤30 days), per PLAN.md vendoring policy.
