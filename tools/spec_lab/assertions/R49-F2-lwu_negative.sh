#!/usr/bin/env bash
# =============================================================================
# R49-F2-lwu_negative.sh — 反向断言: 故意把 lwu 改回 lw, 期望正向抓到
# =============================================================================
set -uo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"
BACKUP="$LAB_DIR/extracted/R49-F2-lwu_negative.bak"

# 1. 备份 lwu 行
LINE=$(grep -n -F "lwu     t0, 0(a1)" "$SRC" | head -1 | cut -d: -f1)
echo "$LINE" > "$BACKUP.line"
sed -n "${LINE}p" "$SRC" > "$BACKUP.original"

# 2. 替换为 lw (R48 错误形态, RV64 符号扩展陷阱)
sed -i "${LINE}s|lwu[[:space:]]*t0,[[:space:]]*0(a1)|lw      t0, 0(a1)              # NEGATIVE TEST|" "$SRC"

# 3. 跑正向断言, 期望失败
set +e
bash "$LAB_DIR/assertions/R49-F2-lwu.sh" >/dev/null 2>&1
RC=$?
set -e

# 4. 复原
sed -i "${LINE}c\\
$(cat "$BACKUP.original")" "$SRC"

if [[ "$RC" -eq 0 ]]; then
  echo "FAIL: R49-F2-lwu_negative — 反例未被抓到, lw 通过了正向断言" >&2
  exit 1
fi

echo "PASS: R49-F2-lwu_negative (反例 lw 确实被正向断言抓到)"
exit 0