#!/usr/bin/env bash
# =============================================================================
# R51-M1-sys-shutdown_negative.sh — 反向断言: 改 SYS_SHUTDOWN 编号期望被抓
# =============================================================================
# 反例: sed 把 0x28 替换为 0x30 (越界值), 期望正向断言抓到
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/14-syscall-api.md"

# 备份
cp "$SRC" "$LAB_DIR/extracted/R51-M1-sys-shutdown.bak"

# 反例: 0x28 → 0x30 (非法偏移). 表格式: | 0x28 | `SYS_SHUTDOWN` => 值在前
sed -i 's@0x28.*SYS_SHUTDOWN@0x30 | SYS_SHUTDOWN  // NEGATIVE: 漂移值@g' "$SRC"

# 跑正向, 期望失败
set +e
bash "$LAB_DIR/assertions/R51-M1-sys-shutdown.sh" >&2
RC=$?
set -e

# 恢复
mv "$LAB_DIR/extracted/R51-M1-sys-shutdown.bak" "$SRC"

if [ "$RC" -ne 0 ]; then
  echo "PASS: R51-M1-sys-shutdown_negative (反例 0x30 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R51-M1-sys-shutdown_negative (反例 0x30 未被抓, RC=$RC)"
  exit 1
fi
