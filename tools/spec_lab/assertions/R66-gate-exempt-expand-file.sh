#!/usr/bin/env bash
# =============================================================================
# R66-gate-exempt-expand-file.sh — FILE 模式金丝雀 (R66-1, D176 §1.5)
# =============================================================================
# 验证 expand_gate_exempt.sh 对 FILE 模式输出正确:
#   - 30-open-questions.md 是 FILE 模式首实例, 整文件每行应在展开中
# =============================================================================
set -euo pipefail

WORK="${PWD}"
EXPAND="$WORK/tools/spec_lab/expand_gate_exempt.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cd "$WORK"
bash "$EXPAND" > "$TMP" 2>/dev/null

MISSING=()
for n in 1 100 500 1000 2000 3500; do
  if ! grep -qF "docs/30-open-questions.md:${n}" "$TMP"; then
    MISSING+=("docs/30-open-questions.md:${n}")
  fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "PASS: R66-expand-file (30 整文件 FILE 展开, 抽样 6 行全在)"
  exit 0
else
  echo "FAIL: R66-expand-file (30 FILE 展开漏行: ${MISSING[*]})" >&2
  exit 1
fi