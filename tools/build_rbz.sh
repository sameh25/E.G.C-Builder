#!/usr/bin/env bash
# Builds E.G.C_Builder_1.28.67.rbz (a plain zip with the extension at its root).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$ROOT/.stage/EGC_Builder"
OUT="$ROOT/dist/E.G.C_Builder_1.28.67.rbz"

rm -rf "$ROOT/.stage"
mkdir -p "$STAGE" "$ROOT/dist"

cp "$ROOT/src/EGC_Builder.rb"        "$ROOT/.stage/"
cp -r "$ROOT/src/EGC_Builder"        "$STAGE/"
cp "$ROOT/docs/AUDIT_REPORT_1.28.67.md" "$STAGE/"
cp "$ROOT/test/sketchup_console_tests.rb" "$STAGE/"

find "$STAGE" -name '*.rb' -exec ruby -c {} \; >/dev/null

cd "$ROOT/.stage"
rm -f "$OUT"
zip -rq "$OUT" EGC_Builder.rb EGC_Builder
echo "built $OUT"
unzip -l "$OUT" | tail -5
