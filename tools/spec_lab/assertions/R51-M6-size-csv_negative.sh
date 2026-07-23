#!/usr/bin/env bash
# =============================================================================
# R51-M6-size-csv_negative.sh — 反向断言: 活代码恢复 --syms --json 期望被抓
# =============================================================================
# 反例: 把活代码块的 --elf-output-style=JSON 替换为 --syms --json (LLVM 18 空表旧旗标),
#       期望正向 FAIL.
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变 — 无原地 sed -i, 无备份复原.
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="docs/13-build-pipeline.md"     # CWD-relative — 正向断言按此相对路径读
POSITIVE="$LAB_DIR/assertions/R51-M6-size-csv.sh"

# 临时沙箱: 只改副本; trap 保证退出(含中断)即清理, 真 spec 永不触碰
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs"
cp "$SRC_REL" "$WORK/$SRC_REL"

# 反例: 活代码块 --elf-output-style=JSON → --syms --json (跳过 OBSOLETED / 注释行)
LINE=$(grep -n 'elf-output-style=JSON' "$WORK/$SRC_REL" | grep -v OBSOLETED | grep -v '#' | head -1 | cut -d: -f1)
sed -i "${LINE}s|--elf-output-style=JSON|--syms --json|" "$WORK/$SRC_REL"

# 跑正向断言 (CWD=副本沙箱), 期望 FAIL
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M6-size-csv_negative (反例 --syms --json 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M6-size-csv_negative (反例 --syms --json 未被抓, RC=$RC)" >&2
  exit 1
fi
