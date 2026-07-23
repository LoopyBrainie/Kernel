#!/usr/bin/env bash
# =============================================================================
# R51-M2-bss-anchor_negative.sh — 反向断言: 把 var 改成 const 期望被抓
# =============================================================================
# 反例: `var shim_state` → `const shim_state` (D-07 原错), 期望正向 FAIL.
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变 — 无原地 sed -i, 无备份复原.
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="docs/06-boot-sequence.md"      # CWD-relative — 正向断言按此相对路径读
POSITIVE="$LAB_DIR/assertions/R51-M2-bss-anchor.sh"

# 临时沙箱: 只改副本; trap 保证退出(含中断)即清理, 真 spec 永不触碰
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs"
cp "$SRC_REL" "$WORK/$SRC_REL"

# 反例: var → const
LINE=$(grep -n 'var shim_state: ShimState = \.{}' "$WORK/$SRC_REL" | head -1 | cut -d: -f1)
sed -i "${LINE}s|var shim_state: ShimState = \.{}|const shim_state: ShimState = .{}  // NEGATIVE: D-07 原错|" "$WORK/$SRC_REL"

# 跑正向断言 (CWD=副本沙箱), 期望 FAIL
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M2-bss-anchor_negative (反例 const 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M2-bss-anchor_negative (反例 const 未被抓, RC=$RC)" >&2
  exit 1
fi
