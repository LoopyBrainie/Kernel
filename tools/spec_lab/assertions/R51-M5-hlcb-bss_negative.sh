#!/usr/bin/env bash
# =============================================================================
# R51-M5-hlcb-bss_negative.sh — 反向断言: 复活 in_kernel_space 期望被抓
# =============================================================================
# 反例: 在 HartLocalControl 段插入未标注 OBSOLETED 的 in_kernel_space 字段, 期望正向 FAIL.
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变 — 无原地 sed -i, 无备份复原.
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="docs/06-boot-sequence.md"      # CWD-relative — 正向断言按此相对路径读
POSITIVE="$LAB_DIR/assertions/R51-M5-hlcb-bss.sh"

# 临时沙箱: 只改副本; trap 保证退出(含中断)即清理, 真 spec 永不触碰
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs"
cp "$SRC_REL" "$WORK/$SRC_REL"

# 反例: 在 R51-M5 锚点后插入复活行 (不含 OBSOLETED)
LINE=$(grep -n 'R51-M5 (D-16)' "$WORK/$SRC_REL" | head -1 | cut -d: -f1)
sed -i "${LINE}a\\    in_kernel_space: bool = true,  // NEGATIVE: 复活 D82" "$WORK/$SRC_REL"

# 跑正向断言 (CWD=副本沙箱), 期望 FAIL
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M5-hlcb-bss_negative (反例 复活 in_kernel_space 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M5-hlcb-bss_negative (反例 复活 in_kernel_space 未被抓, RC=$RC)" >&2
  exit 1
fi
