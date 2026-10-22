#!/usr/bin/env bash
#
# Verifies a packaged .rbz has the exact flat layout SketchUp requires.
#
# Checks:
#   1. root contains EGC_Builder.rb
#   2. root contains exactly one EGC_Builder/ directory
#   3. NO nested EGC_Builder/EGC_Builder path anywhere
#   4. required runtime files and directories are present
#   5. every .rb entry parses
#   6. the registered extension path 'EGC_Builder/main' resolves inside the zip
#
# Exit 0 = installable, 1 = broken.

set -uo pipefail
PKG="${1:?usage: verify_package.sh <file.rbz>}"
FAIL=0

note() { printf '  %s\n' "$1"; }
ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=1; }

echo "== verifying $PKG =="
[ -f "$PKG" ] || { echo "no such file"; exit 1; }
unzip -tqq "$PKG" >/dev/null || { echo "corrupt zip"; exit 1; }

LIST="$(unzip -Z1 "$PKG")"

# 1. root loader
if printf '%s\n' "$LIST" | grep -qx 'EGC_Builder.rb'; then
  ok "root EGC_Builder.rb present"
else
  bad "root EGC_Builder.rb missing"
fi

# 2. exactly one top-level directory
TOPDIRS="$(printf '%s\n' "$LIST" | awk -F/ 'NF>1{print $1}' | sort -u)"
if [ "$TOPDIRS" = "EGC_Builder" ]; then
  ok "exactly one top-level directory (EGC_Builder)"
else
  bad "unexpected top-level entries: $(echo "$TOPDIRS" | tr '\n' ' ')"
fi

# 3. no nesting
if printf '%s\n' "$LIST" | grep -q '^EGC_Builder/EGC_Builder/'; then
  bad "nested EGC_Builder/EGC_Builder detected (the original startup bug)"
else
  ok "no nested EGC_Builder directory"
fi

# 4. required runtime paths
for req in EGC_Builder/main.rb EGC_Builder/loader.rb EGC_Builder/materials.json \
           EGC_Builder/ui/ui.html EGC_Builder/core/ EGC_Builder/model/ \
           EGC_Builder/ops/ EGC_Builder/ui/ EGC_Builder/assets/; do
  if printf '%s\n' "$LIST" | grep -qx -- "$req"; then
    ok "$req"
  else
    bad "missing $req"
  fi
 done

# 5. ruby syntax of every shipped file
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -qq "$PKG" -d "$TMP"
SYNTAX_BAD=0
while IFS= read -r -d '' f; do
  ruby -c "$f" >/dev/null 2>&1 || { bad "syntax error: ${f#$TMP/}"; SYNTAX_BAD=1; }
done < <(find "$TMP" -name '*.rb' -print0)
[ "$SYNTAX_BAD" -eq 0 ] && ok "all .rb files parse"

# 6. the exact path SketchUp registers must exist after extraction
if [ -f "$TMP/EGC_Builder/main.rb" ]; then
  ok "SketchUp 'EGC_Builder/main' resolves after extraction"
else
  bad "SketchUp 'EGC_Builder/main' would NOT resolve"
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "RESULT: installable"; else echo "RESULT: BROKEN"; fi
exit "$FAIL"
