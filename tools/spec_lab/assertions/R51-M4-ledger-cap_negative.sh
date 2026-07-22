#!/usr/bin/env bash
# =============================================================================
# R51-M4-ledger-cap_negative.sh — 反向断言: 改 bss 上限为 16384 期望被抓
# =============================================================================
# 反例: sed 把 bss_max = 8192 替换为 16384 (放宽到 16KB, 违反 D157)
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/13-build-pipeline.md"

LINE=$(grep -n 'bss_max.*8192' "$SRC" | head -1 | cut -d: -f1)
ORIG=$(sed -n "${LINE}p" "$SRC")
echo "$ORIG" > "$LAB_DIR/extracted/R51-M4-ledger-cap_negative.bak"

# 反例: 8192 → 16384
sed -i "${LINE}s|8192|16384|" "$SRC"

set +e
bash "$LAB_DIR/assertions/R51-M4-ledger-cap.sh" >&2
RC=$?
set -e

# 恢复
sed -i "${LINE}c\\${ORIG}" "$SRC"

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M4-ledger-cap_negative (反例 bss=16384 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M4-ledger-cap_negative (反例 bss=16384 未被抓, RC=$RC)"
  exit 1
fi
