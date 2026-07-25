#!/usr/bin/env bash
# =============================================================================
# R66-gate-exempt-expand-self.sh — SELF 模式金丝雀 (R66-1, D176 §1.5)
# =============================================================================
# 验证 expand_gate_exempt.sh 对 SELF 模式输出正确:
#   - 已知 SELF 行 (docs/03-design-decisions.md:168 D109 marker) 应在展开输出中
#
# 不改门禁行为 (R66-1): 仅测展开函数输出, AUDIT_LINE_FILTER 仍是主门禁兜底
# 实现: 把 expand 输出写到 tmp 文件再 grep, 绕过 set -euo pipefail 的管道
# =============================================================================
set -euo pipefail

WORK="${PWD}"
EXPAND="$WORK/tools/spec_lab/expand_gate_exempt.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cd "$WORK"
bash "$EXPAND" > "$TMP" 2>/dev/null

if grep -qF "docs/03-design-decisions.md:168" "$TMP"; then
  echo "PASS: R66-expand-self (docs/03-design-decisions.md:168 SELF 行正确展开)"
  exit 0
else
  echo "FAIL: R66-expand-self (docs/03-design-decisions.md:168 SELF 行未在展开中, expand 函数异常)" >&2
  exit 1
fi