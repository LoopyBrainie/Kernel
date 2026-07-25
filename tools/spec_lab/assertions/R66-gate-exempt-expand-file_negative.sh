#!/usr/bin/env bash
# =============================================================================
# R66-gate-exempt-expand-file_negative.sh — FILE 模式反例金丝雀 (R66-1)
# =============================================================================
# 反例: docs/02-memory-topology.md:1 (非 FILE 模式文件) 不应在展开中
# =============================================================================
set -euo pipefail

WORK="${PWD}"
EXPAND="$WORK/tools/spec_lab/expand_gate_exempt.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cd "$WORK"
bash "$EXPAND" > "$TMP" 2>/dev/null

if grep -qF "docs/02-memory-topology.md:1:" "$TMP"; then
  echo "FAIL: R66-expand-file_negative (docs/02-memory-topology.md:1 不应展开但展开了, FILE 越界)" >&2
  exit 1
fi

echo "PASS: R66-expand-file_negative (docs/02-memory-topology.md:1 不在展开中, FILE 模式边界守约)"
exit 0