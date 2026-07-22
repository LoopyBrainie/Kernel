#!/usr/bin/env bash
# =============================================================================
# R51-M7-strip-mode_negative.sh — 反向断言: strip=true 期望被抓
# =============================================================================
# 反例: sed 把 kernel_strip: bool = false 替换为 true
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/13-build-pipeline.md"

LINE=$(grep -n 'kernel_strip.*false' "$SRC" | head -1 | cut -d: -f1)
ORIG=$(sed -n "${LINE}p" "$SRC")
echo "$ORIG" > "$LAB_DIR/extracted/R51-M7-strip-mode_negative.bak"

# 反例: false → true
sed -i "${LINE}s|false|true|" "$SRC"

set +e
bash "$LAB_DIR/assertions/R51-M7-strip-mode.sh" >&2
RC=$?
set -e

# 恢复
sed -i "${LINE}c\\${ORIG}" "$SRC"

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M7-strip-mode_negative (反例 strip=true 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M7-strip-mode_negative (反例 strip=true 未被抓, RC=$RC)"
  exit 1
fi
