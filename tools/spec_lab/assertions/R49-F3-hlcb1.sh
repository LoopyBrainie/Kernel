#!/usr/bin/env bash
# =============================================================================
# R49-F3-hlcb1.sh — 正向断言: 06 § HLCB_SIZE=1 单 Hart 边界条款必须存在
# =============================================================================
# 抽取源: docs/06-boot-sequence.md, anchor "R49-F3 勘误: HLCB_SIZE=1 单 Hart 边界条款"
# 期望: 抽取出的注释 / 代码围栏内含:
#       1. HLCB_SIZE == 1 字面量 (build.zig 编译期熔断条件)
#       2. @compileError 字面量 (build.zig 熔断机制)
#       3. __hart0_stack_top 字面量 (链接符号 fallback)
# 失败模式: HLCB_SIZE=1 边界条款被遗漏, 单 Hart 构建沿用 ((tp+1)&0)<<SHIFT=0 死循环
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"
ANCHOR="R49-F3 勘误: HLCB_SIZE=1 单 Hart 边界条款"
EXTRACT="$LAB_DIR/extracted/R49-F3-hlcb1.ext"

bash "$LAB_DIR/extract.sh" "$ANCHOR" "$SRC" "$EXTRACT" >&2

# 验证 1: 非注释行必须含 HLCB_SIZE == 1 字面量 (build.zig 编译期熔断条件)
# 注: 同时过滤 asm 的 # 注释 和 zig/c 的 // 注释
if ! grep -vE '^[[:space:]]*(#|//)' "$EXTRACT" | grep -qF 'HLCB_SIZE == 1'; then
  echo "FAIL: R49-F3-hlcb1 抽取的非注释行不含 'HLCB_SIZE == 1' 编译期熔断条件" >&2
  echo "---- 抽取内容 ----" >&2
  cat "$EXTRACT" >&2
  exit 1
fi

# 验证 2: 非注释行必须含 @compileError 字面量 (build.zig 熔断机制)
if ! grep -vE '^[[:space:]]*(#|//)' "$EXTRACT" | grep -qF '@compileError'; then
  echo "FAIL: R49-F3-hlcb1 抽取的非注释行不含 '@compileError' 熔断机制" >&2
  exit 1
fi

# 验证 3: 非注释行必须含 __hart0_stack_top 链接符号 fallback
if ! grep -vE '^[[:space:]]*(#|//)' "$EXTRACT" | grep -qF '__hart0_stack_top'; then
  echo "FAIL: R49-F3-hlcb1 抽取的非注释行不含 '__hart0_stack_top' 链接符号 fallback" >&2
  exit 1
fi

echo "PASS: R49-F3-hlcb1 (06-boot-sequence.md § HLCB_SIZE=1 边界条款已立法)"
exit 0