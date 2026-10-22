# E.G.C Builder v1.28.67 — System Integrity Audit Report

**Release:** 1.28.67 — Full System Integrity, Production Sync & Logic Repair
**Dimensional contract:** unchanged (SHA-256 pinned, 68 frozen values)
**Regression status:** 137/137 headless tests pass · 45/45 in-SketchUp checks pass

---

## 0. Integrity guarantee (how "no value changed" is enforced, not promised)

Every dimension, clearance, kerf, toolpath offset and drill depth/diameter lives in
`core/constants.rb` inside a single `FROZEN` manifest. At load time:

1. every value is deep-frozen (record + value),
2. a SHA-256 fingerprint is computed over a canonical `key=%.6f` serialisation,
3. `EGC::Constants.verify!` compares it to `EXPECTED_FINGERPRINT`.

The extension **refuses to boot** if the fingerprint drifts, and the audit command
re-checks it on demand. So an accidental edit to a contractual number is a hard
startup failure, not a silent wrong size sent to a saw.

Baseline fingerprint for this release:

```
0a4c347975b826b427f848f73d5abb14516e718f14e46dccb819b097984b297f
```

Values that were explicitly preserved (spot-checked by tests):
`SAW_KERF 4.4` · `BORDER_TRIM 10.0` · `STANDARD_COUNTER_HEIGHT 900` ·
`TALL_UNIT_THRESHOLD 1100` · `DRILL_HINGE_DIAMETER 35` · `DRILL_HINGE_DEPTH 13` ·
`DRILL_HINGE_EDGE_OFFSET 22.5` · `DRILL_SHELF_PIN_DIAMETER 5` ·
`DRILL_SHELF_PIN_DEPTH 13` · `RUNNER_CLEARANCE_SIDE 12.5` · `SYSTEM32_PITCH 32`.

---

## 1. Worktop plane isolation & tall clamping — `exec_worktop.rb`

### Root cause
The legacy generator took the counter elevation from
`run.map(&:bounds).max_by { |b| b.max.z }.max.z`. Any cabinet whose box grew — a base
unit edited to 2300 mm, or a tower that had been mis-tagged `:base` — pushed that
maximum up, so the slab was extruded at **2300 mm** and speared the room.

### Repair
| Rule | Implementation |
|---|---|
| Never read `bounds.max.z` | eligibility is `cabinet.effective_tag == :base` only |
| Filter height > 1100 | `height > TALL_UNIT_THRESHOLD` is excluded regardless of tag |
| Auto-reclassify edited units | `Cabinet#effective_tag` derives `:tall` from height, never trusts the stored tag |
| Plane strictly clamped | `ExecWorktop.top_z` is a **constant** (`STANDARD_COUNTER_HEIGHT`), `clamp_plane!` raises on violation |
| Butt termination | a run stops exactly on a tower's side gable (`WORKTOP_SIDE_OVERHANG == 0`), `left/right_termination == :butt` |

`Cabinet#reclassified?` surfaces the reclassification in the audit and in
`AssistantEdit` reports, so a silently-grown base unit is visible.

**Verification:** `ops/exec_worktop` suite (10 tests) + in-SketchUp Test 1.
Notable: a base run abutting a 2300 mm tower still receives a counter, but it
terminates at `x1 == 600.0` and does not intersect the tower volume.

---

## 2. Production & cutlist synchronisation — `assistant_edit.rb`, `cutlist.rb`, `cam.rb`

### Root cause
Dimension edits changed the model but derived artefacts (cutlist rows, DXF, nesting)
read from cached dictionaries, so they retained the pre-edit sizes until a manual
re-insert or model restart.

### Repair — one funnel, contractual ordering
`Cabinet#resize!` is the only mutation path. It performs, in order:

1. commit new width/height/depth,
2. `rebuild!` — regenerate gables, deck, rails, stretchers, back, shelves, doors, drawers,
3. `ProductionSync.after_resize`:
   * **synchronously** re-write every `EGC_PART` dictionary with new *cut* sizes,
   * `Cutlist.invalidate_cache!`,
   * `CAM.reset_toolpaths!`,
   * `Nesting.invalidate_layout!`.

Parts are refreshed **before** caches are dropped, so a cache rebuild can never read
a stale size. `EGC_PART` dictionaries are keyed **per entity** (`EGC_PART_<id>`),
matching SketchUp's per-entity AttributeDictionary semantics — a single shared key
would have made each part overwrite the previous one.

**Verification:** `ops/production_sync` (7 tests) + `ops/assistant_edit` (4 tests) +
in-SketchUp Test 2 (600 → 800 mm: deck and shelf both report
`800 − 2 × 18 = 764 mm`, and the stored attribute agrees with the CSV).

---

## 3. Nesting engine optimisation — `nesting.rb`

Kerf and border trim are **read-only** inputs here; no constant is altered.

| Improvement | Detail |
|---|---|
| Grain-aware rotation | `material.has_grain == false` ⇒ 90° rotation permitted; grained boards never rotate |
| Best-fit placement | each part goes into the **smallest** free rectangle that accepts it, deliberately targeting offcuts left by large gables |
| Guillotine split | both split orientations are scored and the one preserving the larger remainder is chosen |
| Strip grouping | identical-width parts become one continuous rip; strips are **capped at usable sheet length** |
| Material partitioning | parts are grouped by (material, thickness) first — a sheet is one physical board |
| Rotation is never regressive | the packer runs both policies and keeps the better result |

### Defects found and fixed during this work
* Strips were emitted width-first, making any strip longer than the sheet *width*
  unplaceable → 140 orphaned parts on a 20-cabinet job.
* The strip `flush` lambda used `next`, so an oversized part lingered in the buffer
  and was emitted inside the *next* strip → placements outside the trimmed area.
* The comparator preferred fewer sheets over placing all parts; it now ranks
  **fewest unplaced** first, then fewest sheets, then used area.

**Verification:** `ops/nesting` (11 tests) + in-SketchUp Test 3 (20 cabinets:
legal layout, 0 unplaced, rotation exercised, grained boards never rotated).

---

## 4. Dressing room / open wardrobe — `wardrobe.rb`, `space_tool.rb`

### Root cause of `nil:NilClass`
Cavity computation dereferenced `doors.first.face`. On a doorless unit `doors` is
empty, so `first` is `nil` and any shelf/divider insertion raised.

### Repair
`Wardrobe.detect_inner_void` now delegates to `Cabinet#inner_void`, derived **purely**
from carcass panels:

```
x : inner face of left gable  ..  inner face of right gable
y : front face of back panel  ..  open front plane
z : inner face of bottom deck .. underside of the top obstruction
```

No door object is referenced anywhere in this path. The top obstruction is
`TOP_RAIL_HEIGHT` for a base unit (open front rail) and `PANEL_THICKNESS` otherwise.

Open units automatically receive exposed `:front` edge banding on gables, deck,
top and shelves, re-applied after **every** structural change.

`space_tool.rb` single-click resolves the cavity through `cavity_zones` (world-space
boxes) and supports fixed shelf, adjustable shelf, vertical divider, hanging rod
(with bracket drilling at the frozen 5 mm / 13 mm) and drawer modules (runner chosen
by `Hardware.runner_for_depth`, which only *reads* the frozen clearances).

**Verification:** `model/wardrobe` (5 tests) + `ops/space_tool` (12 tests) +
in-SketchUp Test 4 (zero nil errors, all five insertions succeed, gable front edge banded).

---

## 5. System-wide regression & package

* **31 modules** load in dependency order; `Audit.check_modules_loaded` verifies each
  manifest entry exists on disk *and* was actually required.
* **25 suites / 156 tests** headless, **0 failures**.
* **45 checks** in the SketchUp-console suite, **0 failures**.
* Auxiliary tools (`interference`, `corner`, `appliances`, `snap`, `space_tool`) are
  wrapped in a log-audit gate that asserts **zero** warning records.

### Additional real defects found by the suite
| Defect | Impact | Fix |
|---|---|---|
| Back panel spanned full width/height | intersected both gables and the deck | inset into the rebate, `inner_w × (h − 2t)` |
| Rear stretcher sat in the back panel's rebate | 369 984 mm³ interpenetration | moved in front of the back panel |
| Top rail / stretcher created **100 mm thick** | solid block, phantom nesting material group | thickness = `PANEL_THICKNESS`, 100 mm is the rail *width* |
| `internal_depth` used `PANEL_THICKNESS` where the back panel is 8 mm | internal depth 14 mm short | uses `BACK_THICKNESS` |
| `Audit.check_modules_loaded` used `require` to test loading | always reported every module missing | checks the loader's recorded list |

---

## Files delivered

```
EGC_Builder.rb                     extension registration
EGC_Builder/main.rb                deferred bootstrap + integrity gate
EGC_Builder/loader.rb              dependency-ordered manifest (31 modules)
EGC_Builder/materials.json         material data (has_grain drives rotation)
EGC_Builder/core/                  version errors units logger geom constants scene aliases
EGC_Builder/model/                 materials edgeband part hardware carcass doors cabinet wardrobe
EGC_Builder/ops/                   production_sync cutlist cam nesting exec_worktop
                                   assistant_edit space_tool interference corner appliances snap audit
EGC_Builder/ui/                    menu commands dialog + ui.html ui.css ui.js
EGC_Builder/assets/                icon.svg
EGC_Builder/sketchup_console_tests.rb   in-SketchUp verification suite
EGC_Builder/AUDIT_REPORT_1.28.67.md     this report
```

## 6. Packaging repair — the v1.28.67 startup `LoadError` (post-mortem)

### Symptom

```text
Error: LoadError (Could not find such file -- EGC_Builder/main)
  .../SketchUp 2026/SketchUp/Plugins/EGC_Builder.rb:24:in 'register_extension'
```

The engine was healthy; the **archive** was wrong. Every functional suite passed
against `src/`, which is exactly why the defect escaped: the tests never looked
at the built `.rbz`.

### Root cause

`tools/build_rbz.sh` staged the payload like this:

```bash
STAGE="$ROOT/.stage/EGC_Builder"; mkdir -p "$STAGE"   # creates …/EGC_Builder
cp -r "$ROOT/src/EGC_Builder" "$STAGE/"               # copies INTO it
```

`cp -r src/EGC_Builder` into an existing directory named `EGC_Builder` produced
`.stage/EGC_Builder/EGC_Builder/…`. The resulting archive held 38 nested
entries, so Extension Manager extracted:

```text
Plugins/EGC_Builder.rb
Plugins/EGC_Builder/EGC_Builder/main.rb     <- one level too deep
```

`EGC_Builder.rb` registers `'EGC_Builder/main'`, which resolves relative to
`Plugins/`. That file did not exist there, so `register_extension` raised
`LoadError` at boot.

### Fix

Staging now copies the source tree into a **bare** directory so `cp -r` creates
the single `EGC_Builder` level itself, and the build asserts the result before
zipping:

* `find … -mindepth 1 -name EGC_Builder` — aborts on any nested directory
  (`-mindepth 1` is essential; without it `find` matches its own start path and
  every build aborts).
* presence assertions for `loader.rb`, `main.rb`, `materials.json`, `core/`,
  `model/`, `ops/`, `ui/`, `assets/` and `ui/ui.html`.
* `ruby -c` over every shipped `.rb`.
* `tools/verify_package.sh` re-opens the finished archive and proves
  `EGC_Builder/main.rb` resolves after extraction.

### Canonical archive layout (enforced)

```text
EGC_Builder.rb
EGC_Builder/
  loader.rb  main.rb  materials.json
  core/  model/  ops/  ui/  assets/
```

Two root entries only. `EGC_Builder/EGC_Builder/…` must never appear.

### Guard against recurrence

Because the functional suites cannot see the archive, three suites were added
(now **25 suites / 156 tests**): `ui/dialog`, `ui/commands` and `package/layout`.
They assert that every referenced dialog asset exists, that every menu command
has a dispatch handler, that `src/` holds exactly one extension directory, that
no nested `EGC_Builder` exists anywhere, and that the dimensional fingerprint is
still `0a4c347975b826b4…`.

`test/sketchup_console_tests.rb` also had a latent false-pass: its final line was
guarded by `if defined?(Sketchup)`, so a plain-Ruby run executed **zero** checks
and still exited 0. It now bootstraps the engine headless and gates on
`defined?(EGC::ConsoleTests)`, so the 45 checks genuinely run in both hosts.

### Verified

| Check | Result |
|---|---|
| Nested `EGC_Builder/EGC_Builder` entries | **0** (was 38) |
| Root entries | `EGC_Builder.rb`, `EGC_Builder` |
| Entries in archive | 47 |
| `Plugins/EGC_Builder/main.rb` after extraction | exists |
| Boot from extracted package | `BOOT OK v1.28.67`, 31 modules |
| Headless regression | 25 suites, 156 tests, 0 failed |
| Console suite | 45 checks, 0 failed |
| Fingerprint | `0a4c347975b826b4…` (68 values, unchanged) |

## How to verify after installing

```ruby
# SketchUp Ruby Console
load '<extension>/EGC_Builder/sketchup_console_tests.rb'
```

Expected tail:

```
EGC 1.28.67 in-SketchUp test suite: 45 checks, 45 passed, 0 failed
```

## Known limitations

* The `.rbz` ships the engine and its test suite; the interactive SketchUp
  `Tool` subclasses (mouse-driven preview) are represented by `SpaceTool`
  hit-test/highlight/insert APIs rather than a rendered tool session.
* Nesting is a deterministic heuristic, not an exact solver; it reports
  `unplaced` explicitly instead of silently dropping parts.
* `materials.json` may add materials but can never override the built-in
  `has_grain` policy or any frozen thickness.
