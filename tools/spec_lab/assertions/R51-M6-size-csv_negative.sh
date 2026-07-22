#!/usr/bin/env bash
# =============================================================================
# R51-M6-size-csv_negative.sh — 反向断言: 活代码恢复 --syms --json 期望被抓
# =============================================================================
# 反例: sed 把 --elf-output-style=JSON 替换为 --syms --json (旧旗标复活)
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/13-build-pipeline.md"

LINE=$(grep -n 'elf-output-style=JSON' "$SRC" | grep -v OBSOLETED | grep -v '#' | head -1 | cut -d: -f1)
ORIG=$(sed -n "${LINE}p" "$SRC")
echo "$ORIG" > "$LAB_DIR/extracted/R51-M6-size-csv_negative.bak"

# 反例: --elf-output-style=JSON → --syms --json
sed -i "${LINE}s|--elf-output-style=JSON|--syms --json|" "$SRC"

set +e
bash "$LAB_DIR/assertions/R51-M6-size-csv.sh" >&2
RC=$?
set -e

# 恢复
sed -i "${LINE}c\\${ORIG}" "$SRC"

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M6-size-csv_negative (反例 --syms --json 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M6-size-csv_negative (反例 --syms --json 未被抓, RC=$RC)"
  exit 1
fi
