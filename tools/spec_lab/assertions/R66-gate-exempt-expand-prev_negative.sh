#!/usr/bin/env bash
# =============================================================================
# R66-gate-exempt-expand-prev_negative.sh — PREV 模式反例金丝雀 (R66-1)
# =============================================================================
# 反例: docs/01-system-overview.md:23 (PREV 应只覆盖 L20 + L21, 不应溢出 L23)
# =============================================================================
set -euo pipefail

WORK="${PWD}"
EXPAND="$WORK/tools/spec_lab/expand_gate_exempt.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cd "$WORK"
bash "$EXPAND" > "$TMP" 2>/dev/null

if grep -qF "docs/01-system-overview.md:23" "$TMP"; then
  echo "FAIL: R66-expand-prev_negative (docs/01-system-overview.md:23 不应展开但展开了, PREV 段落越界)" >&2
  exit 1
fi

echo "PASS: R66-expand-prev_negative (docs/01-system-overview.md:23 不在展开中, PREV 段落边界守约)"
exit 0