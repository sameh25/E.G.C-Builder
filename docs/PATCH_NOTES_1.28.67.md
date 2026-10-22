# E.G.C Builder v1.28.67 — patch notes

Baseline: **authentic E.G.C_Builder_1.28.66** (97 modules, flat `egc_builder/`, full `assets/`).
This is a **patch** on the production tree, not a rewrite. `core/`, `model/`, `ops/` do not exist here.

| File | Change |
|---|---|
| `egc_builder.rb` | `PLUGIN_VERSION` 1.28.66 → 1.28.67 |
| `egc_builder/kitchen.rb` | `TALL_VOTE_MM`, `tall_vote?`, `slab_reference_h`, `rebuild_local_countertop`, `rebuild_cabinet` |
| `egc_builder/cutlist.rb` | `generation` / `invalidate_cache!`, `grain_free?`, `rotatable?`, `nest_all` |
| `egc_builder/wardrobe.rb` | `interior_sections` |
| `egc_builder/space_tool.rb` | `void_at`, `extras_of` |

Nothing else changed: 494 files, 16 directories, 211 PNG / 135 JPG / 31 SVG, identical to baseline.

## 1. Countertop elevation and tall-unit termination

The bug was in `slab_reference_h`. It filtered towers by the stored `kind` attribute only.
`rebuild_cabinet` rewrites `w`/`h`/`d` but **not** `kind`, so a base unit resized in place to
2300 mm still reported `kind == 'base'`, still won the `max()`, and dragged the whole slab up
with it.

- `TALL_VOTE_MM = 1100.0` and `tall_vote?(g)` — a unit is a tower by **height** or by kind.
- `slab_reference_h` excludes anything `tall_vote?` reports, and clamps the result to
  `cfg['base_h']` so the plane can never exceed counter height.
- `rebuild_local_countertop` drops the same units from the carrying-base list, so a rebuilt
  run stops at the tower's side gable instead of running across its top.

## 2. Edit → cutlist sync

`cutlist.rb` has **no cache** in 1.28.66 (there is nothing to flush). What was missing was a
staleness signal for the consumers that read `'egc'` dictionaries: `Report`, the CSV export,
CAM and the `ProductionModel` snapshot.

- `Cutlist.generation` / `Cutlist.invalidate_cache!` — a monotonic counter.
- `Cutlist.analyse` returns `generation:` alongside its rows.
- `Kitchen.rebuild_cabinet` (the single funnel for every edit, resize, replace and style
  change) advances it after `Panel.add` has rewritten the part dictionaries.

The call is guarded with `defined?`/`respond_to?` and rescued: a resize must never fail
because a production module is not loaded.

## 3. Nesting rotation

Rotation used to read `cfg['grain_lock']`, a two-entry map (`front`, `top`). Every other
material — including wood-veneer carcass — was free to rotate, so grain ran across the part.

- `grain_free?` classifies the board: solid backs / drawers / plinth rotate; a swatch whose
  `cat` is `Wood` or whose texture lives under `/wood/` never rotates.
- `rotatable?` applies authority in order: explicit `grain_lock` entry → swatch grain → default.
- Kerf and trim are untouched. The packer is called exactly as before:
  `Nesting.pack(items, sl, sw, cfg['kerf'].to_f, cfg['trim'].to_f)`.
  Real defaults remain `'kerf' => 4` and `'trim' => 10` in `config.rb`.

## 4. Doorless wardrobes

Door references are gone from the cavity path.

- `Space.void_at` no longer returns `nil` just because no board matched the name `side_l`/`side_r`.
  With no gables it derives the shell from every non-front board, so a unit built with
  `doors: 'none'` still resolves a cavity.
- `Space.extras_of` parsed `params` with `JSON.parse(...)['extras']`. A unit with no params (or
  `null`) raised `JSON::ParserError` or `NoMethodError` on `nil['extras']`. Now read defensively.
- `Wardrobe::Builder#interior_sections` indexed `secs[-1]['w']`; an empty section list made
  that `nil['w'] = ...` → `NoMethodError`. Falls back to the inner gable-to-gable width.

## Verified

| Check | Result |
|---|---|
| Ruby syntax, all modules | 98/98 OK |
| Archive entries | 510 (identical to baseline) |
| Root entries | `egc_builder.rb`, `egc_builder/` |
| Nested `egc_builder/egc_builder` | 0 |
| `Plugins/egc_builder/main.rb` after extraction | exists |
| Assets | 211 PNG / 135 JPG / 31 SVG — unchanged |
| SHA-256 | `9c63f434a8fe10c6c9244bfe5f2ee791e1d60c30177af9a67b48706db6f2fbe2` |

## Not verified

There is no SketchUp in the build environment, so none of this has been executed against the
SketchUp API. The changes are syntax-checked and diff-reviewed only. Please run the build in
SketchUp 2026 and check: a base unit resized to 2300 mm keeps the slab at counter height; the
worktop stops at that unit's gable; a wood carcass no longer rotates in the nest; an open
wardrobe accepts a shelf without a `nil` error.

## Applying

Drop-in replacement: install the `.rbz`, or apply
`patches/v1.28.67-vs-v1.28.66.patch` to a 1.28.66 tree.
