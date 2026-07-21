#!/usr/bin/env bash
# =============================================================================
# R51-F5-rev8_negative.sh — 反向断言: 故意把字节反转改回 rev8 期望被抓
# =============================================================================
# 抽取源: docs/06-boot-sequence.md, anchor "R51-F5 (D-13) byte-swap t0"
# 反例: sed 把 slli+srli 替换为 rev8 t0, t0 (假设 Zbb 的 R47 错误形态)
# 期望: 正向断言 (R51-F5-rev8.sh) 退出非 0; 然后立即恢复
# 通过条件: 反例被正向断言抓 (退出码 0 = 反向 PASS)
# 失败模式: 反例逃过正向断言 → R51-F5-rev8.sh 仍 PASS (反向 FAIL)
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"
ANCHOR="R51-F5 (D-13) byte-swap t0"
EXTRACT="$LAB_DIR/extracted/R51-F5-rev8.ext"

# Find first slli line after anchor
LINE=$(grep -n "$ANCHOR" "$SRC" | head -1 | cut -d: -f1)
LINE=$((LINE + 2)) # first slli 紧邻 anchor 后一行
ORIG=$(sed -n "${LINE}p" "$SRC")
echo "$ORIG" > "$LAB_DIR/extracted/R51-F5-rev8_negative.bak.original"
echo "$LINE" > "$LAB_DIR/extracted/R51-F5-rev8_negative.bak.line"

# 反例: 把 slli 替换为 rev8 (假设 Zbb 不可用)
sed -i "${LINE}s|.*|    rev8    t0, t0                      # NEGATIVE TEST: R47 错误形态 假设 Zbb|" "$SRC"

# 跑正向断言, 期望失败
set +e
bash "$LAB_DIR/assertions/R51-F5-rev8.sh" >&2
RC=$?
set -e

# 恢复
sed -i "${LINE}c\\${ORIG}" "$SRC"

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-F5-rev8_negative (反例 rev8 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-F5-rev8_negative (反例 rev8 未被抓, RC=$RC)"
  exit 1
fi
