# E.G.C Builder

SketchUp extension for cabinet & joinery production: cutlists, nesting, CAM/DXF
export, wardrobe and dressing-room modules.

## Release 1.28.67

Patches applied to the **authentic 1.28.66 production tree** (97 top-level modules +
11 in `proto121/`, full `assets/`). The flat `egc_builder.rb` + `egc_builder/` layout is
unchanged — no `core/`, `model/` or `ops/` directories.

| # | Patch | Files |
|---|---|---|
| 1 | Countertop elevation: towers excluded by **height** (>1100 mm), plane clamped, runs butt-terminate at tall gables | `kitchen.rb` |
| 2 | 3D edit → cutlist sync: generation counter advanced after every `Panel.add` rebuild | `kitchen.rb`, `cutlist.rb` |
| 3 | Nesting rotation: 90° only for grain-free boards; kerf `4` / trim `10` untouched | `cutlist.rb` |
| 4 | Open wardrobe cavities: door references removed from void detection; nil paths fixed | `wardrobe.rb`, `space_tool.rb` |

Full detail: [`docs/PATCH_NOTES_1.28.67.md`](docs/PATCH_NOTES_1.28.67.md)

## Layout

```
work/                 patched plugin source (the build input)
  egc_builder.rb      extension registration, PLUGIN_VERSION
  egc_builder/        97 modules + proto121/ + assets/
baseline/             pristine 1.28.66 extract (diff reference only)
patches/              unified diff, 1.28.66 -> 1.28.67
release/              built .rbz
tools/build_rbz.sh    syntax check + package + verify
tools/verify_package.sh   structural checks on a built .rbz
```

## Building

```bash
tools/build_rbz.sh
```

Runs `ruby -c` over every module, zips `work/` with the plugin at the archive root,
then verifies structure. The build is reproducible: a clean rebuild produces an
identical SHA-256.

## Installing

SketchUp → Extension Manager → *Install Extension* → select
`release/E.G.C_Builder_1.28.67.rbz`. The archive extracts to
`Plugins/egc_builder.rb` and `Plugins/egc_builder/`, which is what
`egc_builder.rb` registers.

Development happens on `genspark_ai_developer`; open a pull request to merge.

## Not verified

No SketchUp is available in the build environment. The patches are syntax-checked and
diff-reviewed only — they have not been executed against the SketchUp API.
