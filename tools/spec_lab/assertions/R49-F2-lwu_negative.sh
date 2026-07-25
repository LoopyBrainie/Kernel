#!/usr/bin/env bash
# =============================================================================
# R49-F2-lwu_negative.sh — 反向断言: 故意把 lwu 改回 lw, 期望正向抓到
# =============================================================================
# 反例: 06 § Step 0 DTB magic 加载 lwu → lw (R48 错误形态, RV64 符号扩展陷阱).
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变 — 无原地 sed -i, 无备份复原.
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="docs/06-boot-sequence.md"      # CWD-relative — 正向断言按此相对路径读
POSITIVE="$LAB_DIR/assertions/R49-F2-lwu.sh"

# 临时沙箱: 只改副本; trap 保证退出(含中断)即清理, 真 spec 永不触碰
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs"
cp "$SRC_REL" "$WORK/$SRC_REL"

# 反例: lwu → lw (R48 错误形态)
LINE=$(grep -n -F "lwu     t0, 0(a1)" "$WORK/$SRC_REL" | head -1 | cut -d: -f1)
sed -i "${LINE}s|lwu[[:space:]]*t0,[[:space:]]*0(a1)|lw      t0, 0(a1)              # NEGATIVE TEST|" "$WORK/$SRC_REL"

# 跑正向断言 (CWD=副本沙箱), 期望 FAIL
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ]; then
  echo "PASS: R49-F2-lwu_negative (反例 lw 确实被正向断言抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R49-F2-lwu_negative — 反例未被抓到, lw 通过了正向断言" >&2
  exit 1
fi
