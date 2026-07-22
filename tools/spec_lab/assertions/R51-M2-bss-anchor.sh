#!/usr/bin/env bash
# =============================================================================
# R51-M2-bss-anchor.sh — 正向断言: 锚点变量必须 var = .{} (非 const)
# =============================================================================
# 抽取源: docs/06-boot-sequence.md, anchor "R51-M2 (D-07)"
# 期望: 锚点变量用 `var shim_state: ShimState = .{}`, 不是 `const`
# 失败模式: 退化回 .rodata const 零初始化 (D-07 原始错误)
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"
ANCHOR="R51-M2 (D-07)"
EXTRACT="$LAB_DIR/extracted/R51-M2-bss-anchor.ext"

bash "$LAB_DIR/extract.sh" "$ANCHOR" "$SRC" "$EXTRACT" >&2

# 验证 1: 必须含 `var shim_state` 字面量 (不是 const)
if ! grep -q 'var shim_state' "$EXTRACT"; then
  echo "FAIL: R51-M2 锚点变量不是 var (可能被 const 替换)" >&2
  echo "---- 抽取内容 ----" >&2
  cat "$EXTRACT" >&2
  exit 1
fi

# 验证 2: 必须用 .{} 零构造
if ! grep -q '\.{}' "$EXTRACT"; then
  echo "FAIL: R51-M2 锚点变量缺 .{} 零构造" >&2
  cat "$EXTRACT" >&2
  exit 1
fi

# 验证 3: 禁止 const
if grep -q 'const.*shim_state.*ShimState' "$EXTRACT"; then
  echo "FAIL: R51-M2 锚点变量被 const 绑定 — 违反 D155" >&2
  exit 1
fi

echo "PASS: R51-M2-bss-anchor (var shim_state: ShimState = .{} 零构造)"
exit 0
