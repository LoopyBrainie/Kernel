#!/usr/bin/env bash
# =============================================================================
# R49-F1-jr_negative.sh — 反向断言: 故意制造 jalr ra, t0 草图, 期望 runner 抓到
# =============================================================================
# 反例机制: 临时把 05-call-gate.md 的 jr t0 行替换为 jalr ra, t0 (R47 错误形态),
#           跑正向断言, 期望 FAIL. 然后复原.
# 通过条件: 反例修改后正向断言确实 FAIL (exit 非 0)
# 这是 "frozen = 编译过的" 的反向防御 — 验证 runner 真能抓烂草图.
# =============================================================================
set -uo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/05-call-gate.md"
BACKUP="$LAB_DIR/extracted/R49-F1-jr_negative.bak"

# 1. 备份当前行号 + 原内容
LINE=$(grep -n -F "jr      t0" "$SRC" | head -1 | cut -d: -f1)
echo "$LINE" > "$BACKUP.line"
sed -n "${LINE}p" "$SRC" > "$BACKUP.original"

# 2. 临时替换为 jalr ra, t0 (R47 错误形态)
sed -i "${LINE}s|jr[[:space:]]*t0.*\$|jalr    ra, t0                 # NEGATIVE TEST: R47 错误形态|" "$SRC"

# 3. 跑正向断言, 期望失败
set +e
bash "$LAB_DIR/assertions/R49-F1-jr.sh" >/dev/null 2>&1
RC=$?
set -e

# 4. 立即复原
sed -i "${LINE}c\\
$(cat "$BACKUP.original")" "$SRC"

# 5. 断言反向验证成功: 正向断言必须失败 (RC != 0)
if [[ "$RC" -eq 0 ]]; then
  echo "FAIL: R49-F1-jr_negative — 反例未被抓到, jalr ra, t0 通过了正向断言" >&2
  exit 1
fi

echo "PASS: R49-F1-jr_negative (反例 jalr ra, t0 确实被正向断言抓到)"
exit 0