#!/usr/bin/env bash
# =============================================================================
# R66-gate-exempt-expand-self_negative.sh — SELF 模式反例金丝雀 (R66-1)
# =============================================================================
# 反例: docs/02-memory-topology.md:5 (非 marker, 非 FILE 模式) 不应在展开中
# =============================================================================
set -euo pipefail

WORK="${PWD}"
EXPAND="$WORK/tools/spec_lab/expand_gate_exempt.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cd "$WORK"
bash "$EXPAND" > "$TMP" 2>/dev/null

if grep -qF "docs/02-memory-topology.md:5:" "$TMP"; then
  echo "FAIL: R66-expand-self_negative (docs/02-memory-topology.md:5 不应展开但展开了, SELF/PREV/FILE 越界)" >&2
  exit 1
fi

echo "PASS: R66-expand-self_negative (docs/02-memory-topology.md:5 不在展开中, SELF/PREV/FILE 边界守约)"
exit 0