#!/usr/bin/env bash
# =============================================================================
# R51-M5-hlcb-bss.sh — 正向断言: HLCB 已删 in_kernel_space, .bss RR 托管
# =============================================================================
# 抽取源: docs/06-boot-sequence.md, anchor "R51-M5 (D-16)"
# 期望: HartLocalControl.in_kernel 存在, in_kernel_space 已标注 OBSOLETED
# 失败模式: in_kernel_space 复活 / HartLocalControl 消失
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"
ANCHOR="R51-M5 (D-16)"
EXTRACT="$LAB_DIR/extracted/R51-M5-hlcb-bss.ext"

bash "$LAB_DIR/extract.sh" "$ANCHOR" "$SRC" "$EXTRACT" >&2

CONTENT=$(cat "$EXTRACT")

# 验证 1: HartLocalControl 结构体定义存在
if ! echo "$CONTENT" | grep -q 'HartLocalControl'; then
  echo "FAIL: R51-M5 HartLocalControl struct 缺失" >&2
  echo "---- 抽取内容 ----" >&2
  echo "$CONTENT" >&2
  exit 1
fi

# 验证 2: in_kernel 字段存在 (新托管)
if ! echo "$CONTENT" | grep -q 'in_kernel'; then
  echo "FAIL: R51-M5 HartLocalControl 缺 in_kernel 字段" >&2
  exit 1
fi

# 验证 3: 在 06 全局范围: in_kernel_space 引用必须标注 OBSOLETED,
#         或出现在审计注释/节标题中 (R51-M5 节头 / "不可编译" 历史描述 / "HLCB 删除" 说明).
if grep -n 'in_kernel_space' "$SRC" \
    | grep -v 'OBSOLETED' \
    | grep -v 'HLCB 删除' \
    | grep -v '删除 in_kernel_space' \
    | grep -v '不可编译' \
    | grep -q .; then
  echo "FAIL: R51-M5 06-boot-sequence.md 含未标注 OBSOLETED 的 in_kernel_space 引用" >&2
  grep -n 'in_kernel_space' "$SRC" | grep -v 'OBSOLETED' | grep -v 'HLCB 删除' | grep -v '不可编译' >&2
  exit 1
fi

echo "PASS: R51-M5-hlcb-bss (HLCB 删 in_kernel_space, .bss HartLocalControl.in_kernel 托管)"
exit 0
