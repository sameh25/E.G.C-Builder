#!/usr/bin/env bash
#
# Builds E.G.C_Builder_1.28.67.rbz with a FLAT root layout.
#
# REQUIRED ARCHIVE STRUCTURE (SketchUp Extension Manager extracts literally):
#
#   EGC_Builder.rb          <- root loader, registers 'EGC_Builder/main'
#   EGC_Builder/            <- exactly ONE top-level directory
#     loader.rb
#     main.rb
#     materials.json
#     core/ model/ ops/ ui/ assets/
#
# HISTORY / WHY THIS FILE WAS REWRITTEN
# -------------------------------------
# The previous script did:
#
#     STAGE="$ROOT/.stage/EGC_Builder"; mkdir -p "$STAGE"
#     cp -r "$ROOT/src/EGC_Builder" "$STAGE/"      # <-- BUG
#
# Pre-creating $STAGE and then copying the source tree *into* it produced
#     .stage/EGC_Builder/EGC_Builder/...
# so the installed extension became
#     Plugins/EGC_Builder/EGC_Builder/main.rb
# while EGC_Builder.rb still asked for 'EGC_Builder/main'. SketchUp then failed
# at boot with:  LoadError -- Could not find such file -- EGC_Builder/main
#
# The fix is to stage into a bare directory and let `cp -r` create the single
# EGC_Builder directory itself, then assert the result before zipping.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE_ROOT="$ROOT/.stage"
OUT="$ROOT/dist/E.G.C_Builder_1.28.67.rbz"

echo "== E.G.C Builder package build =="

rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE_ROOT" "$ROOT/dist"

# Root loader script sits beside (not inside) the extension directory.
cp "$ROOT/src/EGC_Builder.rb" "$STAGE_ROOT/EGC_Builder.rb"

# NOTE: do NOT pre-create $STAGE_ROOT/EGC_Builder. Copying the source tree into
# a bare directory creates exactly one EGC_Builder level.
cp -r "$ROOT/src/EGC_Builder" "$STAGE_ROOT/EGC_Builder"

# Runtime docs + the in-SketchUp test suite ship inside the extension dir.
cp "$ROOT/docs/AUDIT_REPORT_1.28.67.md"      "$STAGE_ROOT/EGC_Builder/"
cp "$ROOT/test/sketchup_console_tests.rb"    "$STAGE_ROOT/EGC_Builder/"

# ---- structural guard: fail the build, never ship a nested archive --------
# -mindepth 1 is essential: without it `find` reports its own starting point
# (the legitimate .../EGC_Builder) and every build would abort.
NESTED="$(find "$STAGE_ROOT/EGC_Builder" -mindepth 1 -type d -name 'EGC_Builder' | head -5)"
if [ -n "$NESTED" ]; then
  echo "FATAL: nested EGC_Builder directory detected:" >&2
  echo "$NESTED" >&2
  exit 1
fi

for req in loader.rb main.rb materials.json core model ops ui assets; do
  if [ ! -e "$STAGE_ROOT/EGC_Builder/$req" ]; then
    echo "FATAL: missing required path EGC_Builder/$req" >&2
    exit 1
  fi
done

if [ ! -f "$STAGE_ROOT/EGC_Builder/ui/ui.html" ]; then
  echo "FATAL: missing EGC_Builder/ui/ui.html" >&2
  exit 1
fi

# ---- syntax check every shipped .rb -------------------------------------
find "$STAGE_ROOT" -name '*.rb' -print0 | while IFS= read -r -d '' f; do
  ruby -c "$f" >/dev/null || { echo "FATAL: syntax error in ${f#$STAGE_ROOT/}" >&2; exit 1; }
done
echo "syntax OK"

# ---- zip -----------------------------------------------------------------
cd "$STAGE_ROOT"
rm -f "$OUT"
# -X strips extra file attributes; the two arguments are the ONLY root entries.
zip -rqX "$OUT" EGC_Builder.rb EGC_Builder

echo "built $OUT"

# ---- post-build verification --------------------------------------------
"$ROOT/tools/verify_package.sh" "$OUT"
