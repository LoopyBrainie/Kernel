#!/usr/bin/env bash
# =============================================================================
# R51-M7-strip-mode.sh — 正向断言: ReleaseSmall 必须 -Dstrip=false
# =============================================================================
# 抽取源: docs/13-build-pipeline.md, anchor "R51-M7"
# 期望: kernel_strip 显式设为 false, build.zig 强制 -Dstrip=false
# 失败模式: 默认 strip 让 nm/readobj 空表空真过 (D-21)
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/13-build-pipeline.md"
ANCHOR="R51-M7"
EXTRACT="$LAB_DIR/extracted/R51-M7-strip-mode.ext"

bash "$LAB_DIR/extract.sh" "$ANCHOR" "$SRC" "$EXTRACT" >&2

CONTENT=$(cat "$EXTRACT")

# 验证 1: kernel_strip 显式 false (精确匹配赋值, 不跨注释)
if ! echo "$CONTENT" | grep -qE 'kernel_strip:\s*bool\s*=\s*false'; then
  echo "FAIL: R51-M7 kernel_strip 非显式 false" >&2
  echo "---- 抽取内容 ----" >&2
  echo "$CONTENT" >&2
  exit 1
fi

# 验证 2: 全文件范围: ReleaseSmall 描述必须关联 strip=false
if ! grep -q 'strip=false' "$SRC"; then
  echo "FAIL: R51-M7 13-build-pipeline.md 全文件缺 -Dstrip=false" >&2
  exit 1
fi

echo "PASS: R51-M7-strip-mode (kernel_strip: bool = false, -Dstrip=false 显式)"
exit 0
