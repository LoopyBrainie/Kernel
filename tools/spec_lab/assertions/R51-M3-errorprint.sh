#!/usr/bin/env bash
# =============================================================================
# R51-M3-errorprint.sh — 正向断言: error_pack 打印格式三字段必齐
# =============================================================================
# 抽取源: docs/10-error-handling.md, line 34
# 期望: `error: code=%d  sub=0x%04X node=0x%04X` 三字段 (code/sub/node) 均出现
# 失败模式: 字段缺失 / node= 缺 padding / sub= 消失
# =============================================================================
set -euo pipefail

SRC="docs/10-error-handling.md"

TEXT=$(grep -n 'error: code=' "$SRC" | head -5)

# 验证 1: 必须含 `error: code=%d`
if ! echo "$TEXT" | grep -q 'error: code=%d'; then
  echo "FAIL: R51-M3 error print 缺 code= 字段" >&2
  exit 1
fi

# 验证 2: 必须含 `sub=0x%04X` (含 padding)
if ! echo "$TEXT" | grep -q 'sub=0x%04X'; then
  echo "FAIL: R51-M3 error print 缺 sub=0x%04X (或 padding 丢失)" >&2
  exit 1
fi

# 验证 3: 必须含 `node=0x%04X` (含 padding)
if ! echo "$TEXT" | grep -q 'node=0x%04X'; then
  echo "FAIL: R51-M3 error print 缺 node=0x%04X (或 padding 丢失)" >&2
  exit 1
fi

echo "PASS: R51-M3-errorprint (error: code=%d sub=0x%04X node=0x%04X 三字段齐)"
exit 0
