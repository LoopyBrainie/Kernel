#!/usr/bin/env bash
# =============================================================================
# R51-M2-bss-anchor_negative.sh — 反向断言: 把 var 改成 const 期望被抓
# =============================================================================
# 反例: sed 把 `var shim_state` 替换为 `const shim_state`, 期望正向 fail
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"

LINE=$(grep -n 'var shim_state: ShimState = \.{}' "$SRC" | head -1 | cut -d: -f1)
ORIG=$(sed -n "${LINE}p" "$SRC")
echo "$ORIG" > "$LAB_DIR/extracted/R51-M2-bss-anchor_negative.bak"

# 反例: var → const
sed -i "${LINE}s|var shim_state: ShimState = \.{}|const shim_state: ShimState = .{}  // NEGATIVE: D-07 原错|" "$SRC"

set +e
bash "$LAB_DIR/assertions/R51-M2-bss-anchor.sh" >&2
RC=$?
set -e

# 恢复
sed -i "${LINE}c\\${ORIG}" "$SRC"

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M2-bss-anchor_negative (反例 const 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M2-bss-anchor_negative (反例 const 未被抓, RC=$RC)"
  exit 1
fi
