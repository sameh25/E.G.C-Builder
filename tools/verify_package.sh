#!/usr/bin/env bash
# Structural verification of a built E.G.C Builder .rbz.
# Usage: tools/verify_package.sh release/E.G.C_Builder_1.28.67.rbz
set -euo pipefail

ARTIFACT="${1:-}"
[[ -n "$ARTIFACT" && -f "$ARTIFACT" ]] || { echo "usage: $0 <file.rbz>" >&2; exit 1; }

pass=0; fail=0
ok()   { echo "  PASS  $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail+1)); }

echo "==> $ARTIFACT"

unzip -tq "$ARTIFACT" >/dev/null 2>&1 && ok "zip integrity" || bad "zip integrity"

entries="$(unzip -Z1 "$ARTIFACT")"
total="$(printf '%s\n' "$entries" | wc -l)"
echo "  info  $total entries"

# Root must hold exactly egc_builder.rb and egc_builder/
roots="$(printf '%s\n' "$entries" | awk -F/ '{print $1}' | sort -u)"
[[ "$roots" == "$(printf 'egc_builder\negc_builder.rb')" ]] && ok "root is egc_builder.rb + egc_builder/" \
  || bad "unexpected root entries: $(echo "$roots" | tr '\n' ' ')"

nested="$(printf '%s\n' "$entries" | grep -c '^egc_builder/egc_builder/' || true)"
[[ "$nested" -eq 0 ]] && ok "no nested egc_builder/egc_builder" || bad "$nested nested entries"

printf '%s\n' "$entries" | grep -qx 'egc_builder/main.rb' \
  && ok "egc_builder/main.rb present (registered path resolves)" \
  || bad "egc_builder/main.rb missing"

ver="$(unzip -p "$ARTIFACT" egc_builder.rb | sed -n "s/.*PLUGIN_VERSION *= *'\([^']*\)'.*/\1/p" | head -1)"
[[ -n "$ver" ]] && ok "PLUGIN_VERSION = $ver" || bad "PLUGIN_VERSION unreadable"

# 1.28.67 countertop guard must survive into the package, not just the work tree.
guards="$(unzip -p "$ARTIFACT" egc_builder/kitchen.rb | grep -c 'TALL_VOTE_MM' || true)"
[[ "$guards" -gt 0 ]] && ok "countertop guard present in packaged kitchen.rb" \
  || bad "countertop guard missing from package"

printf '%s\n' "$entries" | grep -q "^egc_builder/assets/" \
  && ok "assets/ bundled" || bad "assets/ missing"

echo "  info  assets: $(printf '%s\n' "$entries" | grep -ci '\.png$' || true) PNG / $(printf '%s\n' "$entries" | grep -ci '\.jpg$' || true) JPG / $(printf '%s\n' "$entries" | grep -ci '\.svg$' || true) SVG"

echo
if [[ $fail -gt 0 ]]; then
  echo "RESULT: $fail failed, $pass passed"
  exit 1
fi
echo "RESULT: all $pass checks passed"
