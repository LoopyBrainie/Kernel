#!/usr/bin/env bash
# =============================================================================
# R51-M5-hlcb-bss_negative.sh — 反向断言: 复活 in_kernel_space 期望被抓
# =============================================================================
# 反例: sed 在 HartLocalControl 段插入 in_kernel_space 字段, 期望正向 fail
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"

LINE=$(grep -n 'R51-M5 (D-16)' "$SRC" | head -1 | cut -d: -f1)
ORIG_BLOCK=$(sed -n "${LINE},$((LINE + 15))p" "$SRC")
echo "$ORIG_BLOCK" > "$LAB_DIR/extracted/R51-M5-hlcb-bss_negative.bak"

# 反例: 在 in_kernel 字段后插入复活行 (不含 OBSOLETED)
sed -i "${LINE}a\\    in_kernel_space: bool = true,  // NEGATIVE: 复活 D82" "$SRC"

set +e
bash "$LAB_DIR/assertions/R51-M5-hlcb-bss.sh" >&2
RC=$?
set -e

# 恢复: 删掉插入行
sed -i '/NEGATIVE: 复活 D82/d' "$SRC"

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M5-hlcb-bss_negative (反例 复活 in_kernel_space 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M5-hlcb-bss_negative (反例 复活 in_kernel_space 未被抓, RC=$RC)"
  exit 1
fi
