#!/usr/bin/env bash
# =============================================================================
# R51-M4-ledger-cap_negative.sh — 反向断言: 改 bss 上限为 16384 期望被抓
# =============================================================================
# 反例: bss_max 8192 → 16384 (放宽到 16KB, 违反 D157), 期望正向 FAIL.
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变 — 无原地 sed -i, 无备份复原.
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="docs/13-build-pipeline.md"     # CWD-relative — 正向断言按此相对路径读
POSITIVE="$LAB_DIR/assertions/R51-M4-ledger-cap.sh"

# 临时沙箱: 只改副本; trap 保证退出(含中断)即清理, 真 spec 永不触碰
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs"
cp "$SRC_REL" "$WORK/$SRC_REL"

# 反例: 8192 → 16384
LINE=$(grep -n 'bss_max.*8192' "$WORK/$SRC_REL" | head -1 | cut -d: -f1)
sed -i "${LINE}s|8192|16384|" "$WORK/$SRC_REL"

# 跑正向断言 (CWD=副本沙箱), 期望 FAIL
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M4-ledger-cap_negative (反例 bss=16384 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M4-ledger-cap_negative (反例 bss=16384 未被抓, RC=$RC)" >&2
  exit 1
fi
