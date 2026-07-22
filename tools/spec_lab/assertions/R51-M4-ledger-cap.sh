#!/usr/bin/env bash
# =============================================================================
# R51-M4-ledger-cap.sh — 正向断言: 02 台账段上限固化 (4 字段)
# =============================================================================
# 抽取源: docs/13-build-pipeline.md, anchor "R51-M4"
# 期望: text≤81920 rodata≤10240 data≤4096 bss≤8192 + @compileError 熔断
# 失败模式: 任一上限漂移 / @compileError 消失 (门禁空转)
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/13-build-pipeline.md"
ANCHOR="R51-M4"
EXTRACT="$LAB_DIR/extracted/R51-M4-ledger-cap.ext"

bash "$LAB_DIR/extract.sh" "$ANCHOR" "$SRC" "$EXTRACT" >&2

CONTENT=$(cat "$EXTRACT")

# 验证 1: 四字段上限值
CHECKS=(
  "text_max.*81920"
  "rodata_max.*10240"
  "data_max.*4096"
  "bss_max.*8192"
)
for check in "${CHECKS[@]}"; do
  if ! echo "$CONTENT" | grep -qE "$check"; then
    echo "FAIL: R51-M4 ledger_caps 缺失: $check" >&2
    echo "---- 抽取内容 ----" >&2
    echo "$CONTENT" >&2
    exit 1
  fi
done

# 验证 2: @compileError 熔断存在
if ! echo "$CONTENT" | grep -q '@compileError'; then
  echo "FAIL: R51-M4 缺 @compileError 熔断 (门禁空转风险)" >&2
  exit 1
fi

echo "PASS: R51-M4-ledger-cap (text≤80KB rodata≤10KB data≤4KB bss≤8KB + @compileError)"
exit 0
