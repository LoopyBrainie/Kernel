#!/usr/bin/env bash
# =============================================================================
# R66-gate-exempt-expand-prev.sh — PREV 模式金丝雀 (R66-1, D176 §1.5)
# =============================================================================
# 验证 expand_gate_exempt.sh 对 PREV 模式输出正确:
#   - 已知 PREV 行 (docs/01-system-overview.md:20 marker → 覆盖 L21)
# =============================================================================
set -euo pipefail

WORK="${PWD}"
EXPAND="$WORK/tools/spec_lab/expand_gate_exempt.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cd "$WORK"
bash "$EXPAND" > "$TMP" 2>/dev/null

if grep -qF "docs/01-system-overview.md:21:" "$TMP"; then
  echo "PASS: R66-expand-prev (docs/01-system-overview.md:21 PREV 展开正确)"
  exit 0
else
  echo "FAIL: R66-expand-prev (docs/01-system-overview.md:21 未在展开中, PREV 特判失效)" >&2
  exit 1
fi