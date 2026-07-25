#!/usr/bin/env bash
# =============================================================================
# R49-F1-jr_negative.sh — 反向断言: 故意制造 jalr ra, t0 草图, 期望 runner 抓到
# =============================================================================
# 反例机制: 把 05 § entry_call_gate.S 的 jr t0 行替换为 jalr ra, t0 (R47 错误形态),
#           跑正向断言, 期望 FAIL. 这是 "frozen = 编译过的" 的反向防御.
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变 — 无原地 sed -i, 无备份复原.
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="docs/05-call-gate.md"          # CWD-relative — 正向断言按此相对路径读
POSITIVE="$LAB_DIR/assertions/R49-F1-jr.sh"

# 临时沙箱: 只改副本; trap 保证退出(含中断)即清理, 真 spec 永不触碰
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs"
cp "$SRC_REL" "$WORK/$SRC_REL"

# 反例: jr t0 → jalr ra, t0 (R47 错误形态)
LINE=$(grep -n -F "jr      t0" "$WORK/$SRC_REL" | head -1 | cut -d: -f1)
sed -i "${LINE}s|jr[[:space:]]*t0.*\$|jalr    ra, t0                 # NEGATIVE TEST: R47 错误形态|" "$WORK/$SRC_REL"

# 跑正向断言 (CWD=副本沙箱), 期望 FAIL
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ]; then
  echo "PASS: R49-F1-jr_negative (反例 jalr ra, t0 确实被正向断言抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R49-F1-jr_negative — 反例未被抓到, jalr ra, t0 通过了正向断言" >&2
  exit 1
fi
