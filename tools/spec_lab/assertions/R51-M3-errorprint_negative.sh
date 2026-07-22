#!/usr/bin/env bash
# =============================================================================
# R51-M3-errorprint_negative.sh — 反向断言: 删 node= 字段期望被抓
# =============================================================================
# 反例: sed 把 `node=0x%04X` 删掉 (只剩 code + sub), 期望正向 fail
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/10-error-handling.md"

LINE=$(grep -n 'error: code=%d.*sub=0x%04X.*node=0x%04X' "$SRC" | head -1 | cut -d: -f1)
ORIG=$(sed -n "${LINE}p" "$SRC")
echo "$ORIG" > "$LAB_DIR/extracted/R51-M3-errorprint_negative.bak"

# 反例: 删 node= 字段
sed -i "${LINE}s| node=0x%04X||" "$SRC"

set +e
bash "$LAB_DIR/assertions/R51-M3-errorprint.sh" >&2
RC=$?
set -e

# 恢复
sed -i "${LINE}c\\${ORIG}" "$SRC"

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M3-errorprint_negative (反例 缺 node= 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M3-errorprint_negative (反例 缺 node= 未被抓, RC=$RC)"
  exit 1
fi
