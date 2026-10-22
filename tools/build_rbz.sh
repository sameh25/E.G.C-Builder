#!/usr/bin/env bash
# Build E.G.C Builder .rbz from the authentic flat plugin tree.
#
# Source:  work/            egc_builder.rb  +  egc_builder/   (flat, one directory)
# Output:  release/E.G.C_Builder_<version>.rbz
#
# The archive MUST extract to Plugins/egc_builder.rb and Plugins/egc_builder/.
# That means the zip root holds exactly those two entries - no wrapping folder,
# no nested egc_builder/egc_builder. Extension Manager extracts literally, and
# egc_builder.rb registers 'egc_builder/main'.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/work"
OUT_DIR="$ROOT/release"

[[ -f "$SRC/egc_builder.rb" ]]      || { echo "missing $SRC/egc_builder.rb" >&2; exit 1; }
[[ -d "$SRC/egc_builder" ]]         || { echo "missing $SRC/egc_builder/" >&2; exit 1; }
[[ -d "$SRC/egc_builder/assets" ]]  || { echo "missing $SRC/egc_builder/assets/" >&2; exit 1; }
[[ -f "$SRC/egc_builder/main.rb" ]] || { echo "missing $SRC/egc_builder/main.rb" >&2; exit 1; }

VERSION="$(sed -n "s/.*PLUGIN_VERSION *= *'\([^']*\)'.*/\1/p" "$SRC/egc_builder.rb" | head -1)"
[[ -n "$VERSION" ]] || { echo "cannot read PLUGIN_VERSION" >&2; exit 1; }

echo "==> syntax check"
fail=0
while IFS= read -r -d '' f; do
  ruby -c "$f" >/dev/null 2>&1 || { echo "   SYNTAX FAIL: $f" >&2; fail=1; }
done < <(find "$SRC" -name '*.rb' -print0)
[[ $fail -eq 0 ]] || { echo "aborting: syntax errors" >&2; exit 1; }
echo "    all $(find "$SRC" -name '*.rb' | wc -l) modules OK"

mkdir -p "$OUT_DIR"
ARTIFACT="$OUT_DIR/E.G.C_Builder_${VERSION}.rbz"
rm -f "$ARTIFACT"

echo "==> packaging $VERSION"
# -X drops extra file attributes so the archive is reproducible.
(cd "$SRC" && zip -rqX "$ARTIFACT" egc_builder.rb egc_builder)

echo "==> built $ARTIFACT"
ls -l "$ARTIFACT"
sha256sum "$ARTIFACT"

"$ROOT/tools/verify_package.sh" "$ARTIFACT"
