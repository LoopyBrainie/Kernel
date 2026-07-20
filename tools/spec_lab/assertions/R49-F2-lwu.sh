#!/usr/bin/env bash
# =============================================================================
# R49-F2-lwu.sh — 正向断言: 06 § Step 0 DTB magic 加载应为 lwu
# =============================================================================
# 抽取源: docs/06-boot-sequence.md, anchor "R49-F2 勘误: lw → lwu"
# 期望: 抽取出的 asm 围栏内含 `lwu t0, 0(a1)`, 不应含裸 `lw      t0, 0(a1)` (R48 错误形态)
# 失败模式: 任何后续 commit 把 lw 复活 (RV64 符号扩展陷阱, 沙箱二 2026-07-19 O3)
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"
ANCHOR="R49-F2 勘误: lw → lwu"
EXTRACT="$LAB_DIR/extracted/R49-F2-lwu.ext"

bash "$LAB_DIR/extract.sh" "$ANCHOR" "$SRC" "$EXTRACT" >&2

# 验证 1: 必须含 lwu t0, 0(a1)
if ! grep -qE 'lwu[[:space:]]+t0,[[:space:]]*0\(a1\)' "$EXTRACT"; then
  echo "FAIL: R49-F2-lwu 抽取内容不含 'lwu t0, 0(a1)'" >&2
  echo "---- 抽取内容 ----" >&2
  cat "$EXTRACT" >&2
  exit 1
fi

# 验证 2: 不应出现裸 `lw      t0, 0(a1)` 作为当前指令
if grep -qE '^[[:space:]]*lw[[:space:]]+t0,[[:space:]]*0\(a1\)' "$EXTRACT"; then
  echo "FAIL: R49-F2-lwu 仍以 lw 作为当前指令 (RV64 符号扩展陷阱未修复)" >&2
  exit 1
fi

echo "PASS: R49-F2-lwu (06-boot-sequence.md § Step 0 DTB magic 加载已勘误为 lwu)"
exit 0