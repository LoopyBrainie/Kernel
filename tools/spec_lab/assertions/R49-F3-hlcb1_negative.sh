#!/usr/bin/env bash
# =============================================================================
# R49-F3-hlcb1_negative.sh — 反向断言: 故意删 @compileError 行, 期望正向抓到
# =============================================================================
# 反例机制:
#   - 找到 R49-F3 块内的 @compileError 行 (zig 围栏内)
#   - 整行替换为反例注释行
#   - 跑正向断言 (期望失败: 非注释行没了 @compileError / HLCB_SIZE == 1 / __hart0_stack_top)
#   - 立即复原
# 通过条件: 正向断言退出非 0 (反例被抓到)
# =============================================================================
set -uo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"

# 1. 备份原文件, 反例在副本上做, 副本替换原文件
ORIG_BAK="$LAB_DIR/extracted/R49-F3-hlcb1_negative.bak.md"
cp "$SRC" "$ORIG_BAK"

# 2. 找 @compileError 行, 整行替换为反例注释
#    用 awk: NR == line { print REPLACEMENT; next }
LINE=$(grep -n -F '@compileError("R49-F3:' "$SRC" | head -1 | cut -d: -f1)
if [[ -z "$LINE" ]]; then
  echo "ERR: R49-F3-hlcb1_negative — 找不到 @compileError 行" >&2
  exit 2
fi

awk -v line="$LINE" '
  NR == line { print "    // NEGATIVE: 反例, @compileError 行被故意整行注释化"; next }
  { print }
' "$SRC" > "$SRC.tmp" && mv "$SRC.tmp" "$SRC"

# 3. 跑正向断言, 期望失败 (非注释行没了 @compileError)
set +e
bash "$LAB_DIR/assertions/R49-F3-hlcb1.sh" >/dev/null 2>&1
RC=$?
set -e

# 4. 立即复原 (从备份还原, 不依赖 sed 替换)
cp "$ORIG_BAK" "$SRC"
rm -f "$ORIG_BAK"

# 5. 断言反向验证成功
if [[ "$RC" -eq 0 ]]; then
  echo "FAIL: R49-F3-hlcb1_negative — 反例未被抓到, 缺 @compileError 也通过了正向断言" >&2
  exit 1
fi

echo "PASS: R49-F3-hlcb1_negative (反例缺 @compileError 确实被正向断言抓到)"
exit 0