#!/usr/bin/env bash
# =============================================================================
# R49-F1-jr.sh — 正向断言: 05 § entry_call_gate.S 第一行应为 jr t0
# =============================================================================
# 抽取源: docs/05-call-gate.md, anchor "R49-F1 勘误: 改回 jr t0 尾调用"
# 期望: 抽取出的 asm 围栏内含 `jr t0`, 不应含 `jalr ra, t0` (jalr 是 R47 错误草图)
# 通过条件: grep 命中 jr t0 + 不含 jalr ra, t0
# 失败模式: R47 错误归因复活 (jalr ra, t0 出现)
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/05-call-gate.md"
ANCHOR="R49-F1 勘误: 改回 jr t0 尾调用"
EXTRACT="$LAB_DIR/extracted/R49-F1-jr.ext"

bash "$LAB_DIR/extract.sh" "$ANCHOR" "$SRC" "$EXTRACT" >&2

# 验证 1: 非注释行必须含 jr t0 (当前指令)
if ! grep -vE '^[[:space:]]*#' "$EXTRACT" | grep -qE 'jr[[:space:]]+t0'; then
  echo "FAIL: R49-F1-jr 抽取的非注释行不含 'jr t0' 当前指令" >&2
  echo "---- 抽取内容 ----" >&2
  cat "$EXTRACT" >&2
  exit 1
fi

# 验证 2: 非注释行必须不含 jalr ra, t0 (R47 错误形态的反向防御)
# 注: 注释里可以提 jalr (描述 Phase 1+ 形态), 指令行不行
if grep -vE '^[[:space:]]*#' "$EXTRACT" | grep -qE 'jalr[[:space:]]+ra,[[:space:]]*t0'; then
  echo "FAIL: R49-F1-jr 指令行仍含 R47 错误草图 'jalr ra, t0' — 错误归因复活" >&2
  exit 1
fi

echo "PASS: R49-F1-jr (05-call-gate.md § entry_call_gate.S 已勘误为 jr t0)"
exit 0