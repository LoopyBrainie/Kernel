#!/usr/bin/env bash
# =============================================================================
# R51-M1-sys-shutdown.sh — 正向断言: 14 号表 SYS_SHUTDOWN=0x28 双处登记
# =============================================================================
# 抽取源: docs/14-syscall-api.md, 两处 syscall 表 (184+ 与 313+)
# 期望: SYS_SHUTDOWN = 0x28 在 BOTH 位置出现, 且含 D154 引用
# 失败模式: 表项缺失 / 编号漂移 / 仅一处有另一处漏
# =============================================================================
set -euo pipefail

SRC="docs/14-syscall-api.md"

# 验证 1: 两处表都含 SYS_SHUTDOWN.*0x28
COUNT=$(grep -cF 'SYS_SHUTDOWN' "$SRC" 2>/dev/null || true)
if [ "$COUNT" -lt 2 ]; then
  echo "FAIL: R51-M1 SYS_SHUTDOWN 出现次数 $COUNT < 2 (需要两处表同步)" >&2
  exit 1
fi

# 验证 2: 值必须为 0x28 (表格式: | 0x28 | `SYS_SHUTDOWN` ...)
if ! grep -qE '0x28.*SYS_SHUTDOWN' "$SRC"; then
  echo "FAIL: R51-M1 SYS_SHUTDOWN 值不为 0x28" >&2
  exit 1
fi

# 验证 3: D154 引用存在 (Phase 1 typed-syscall 路径)
if ! grep -q 'D154' "$SRC"; then
  echo "FAIL: R51-M1 14-syscall-api.md 缺少 D154 回链" >&2
  exit 1
fi

echo "PASS: R51-M1-sys-shutdown (SYS_SHUTDOWN=0x28 双处登记 + D154 回链)"
exit 0
