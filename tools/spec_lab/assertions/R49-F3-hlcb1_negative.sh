#!/usr/bin/env bash
# =============================================================================
# R49-F3-hlcb1_negative.sh — 反向断言: 故意删 @compileError 行, 期望正向抓到
# =============================================================================
# 反例: 把 R49-F3 块内 @compileError 行整行注释化, 跑正向断言, 期望 FAIL
#       (非注释行没了 @compileError / HLCB_SIZE==1 熔断条件).
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变 — 无原地 awk 重写, 无备份复原.
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="docs/06-boot-sequence.md"      # CWD-relative — 正向断言按此相对路径读
POSITIVE="$LAB_DIR/assertions/R49-F3-hlcb1.sh"

# 临时沙箱: 只改副本; trap 保证退出(含中断)即清理, 真 spec 永不触碰
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs"
cp "$SRC_REL" "$WORK/$SRC_REL"

# 反例: 找 @compileError 行, 整行替换为反例注释 (副本上做)
LINE=$(grep -n -F '@compileError("R49-F3:' "$WORK/$SRC_REL" | head -1 | cut -d: -f1)
awk -v line="$LINE" '
  NR == line { print "    // NEGATIVE: 反例, @compileError 行被故意整行注释化"; next }
  { print }
' "$WORK/$SRC_REL" > "$WORK/$SRC_REL.tmp" && mv "$WORK/$SRC_REL.tmp" "$WORK/$SRC_REL"

# 跑正向断言 (CWD=副本沙箱), 期望 FAIL
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ]; then
  echo "PASS: R49-F3-hlcb1_negative (反例缺 @compileError 确实被正向断言抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R49-F3-hlcb1_negative — 反例未被抓到, 缺 @compileError 也通过了正向断言" >&2
  exit 1
fi
