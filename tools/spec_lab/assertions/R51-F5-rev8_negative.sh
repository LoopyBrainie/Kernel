#!/usr/bin/env bash
# =============================================================================
# R51-F5-rev8_negative.sh — 反向断言: 故意把字节反转改回 rev8 期望被抓
# =============================================================================
# 反例: 把 slli+srli 替换为 rev8 t0, t0 (假设 Zbb 的 R47 错误形态), 期望正向 FAIL.
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变 — 无原地 sed -i, 无备份复原.
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="docs/06-boot-sequence.md"      # CWD-relative — 正向断言按此相对路径读
ANCHOR="R51-F5 (D-13) byte-swap t0"
POSITIVE="$LAB_DIR/assertions/R51-F5-rev8.sh"

# 临时沙箱: 只改副本; trap 保证退出(含中断)即清理, 真 spec 永不触碰
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs"
cp "$SRC_REL" "$WORK/$SRC_REL"

# 反例: 把 anchor 后第一条 slli 替换为 rev8 (假设 Zbb 不可用)
LINE=$(grep -n "$ANCHOR" "$WORK/$SRC_REL" | head -1 | cut -d: -f1)
LINE=$((LINE + 2))   # first slli 紧邻 anchor 后一行
sed -i "${LINE}s|.*|    rev8    t0, t0                      # NEGATIVE TEST: R47 错误形态 假设 Zbb|" "$WORK/$SRC_REL"

# 跑正向断言 (CWD=副本沙箱), 期望 FAIL
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-F5-rev8_negative (反例 rev8 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-F5-rev8_negative (反例 rev8 未被抓, RC=$RC)" >&2
  exit 1
fi
