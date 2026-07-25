#!/usr/bin/env bash
# =============================================================================
# S1-sys-shutdown-real-hit.sh — SYS_SHUTDOWN 真违规金丝雀 (R66-3 S1 改真硬判据)
# =============================================================================
# 测试: 在 mktemp 副本中注入一行裸 SYS_SHUTDOWN (无 marker), check-docs.sh 必须 exit 1
#       即便所有 5 行 D154 marker (03:297/312 + 08:616 + 14:185/316) 兜底既有合规命中,
#       真裸 SYS_SHUTDOWN 出现仍必被抓 (因 D176 marker 机制是逐行精确,非 substring 静默豁免).
# 注: R66-3 S1 改真历史 — 原惰性 27 字符串 `SYS_SHUTDOWN.*typed-syscall` 0 真命中, 改纯字符串后
#     任何 SYS_SHUTDOWN 字面量出现必被抓, 5 合规行靠 D154 marker 白名单兜底.
# =============================================================================
set -euo pipefail

WORK="${PWD}"
TEST_FILE="docs/01-system-overview.md"  # 1X 子系统文档 (无 SYS_SHUTDOWN/marker 历史命中)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -r "$WORK" "$TMP/repo"
cd "$TMP/repo"

# 注入真禁词 (SYS_SHUTDOWN, 无 marker, R66-3 S1 改真后必抓)
echo "" >> "$TEST_FILE"
echo "**S1 R66-3 canary**: 注入真禁词 \`SYS_SHUTDOWN\` (无 marker, 改真后纯字符串必抓)" >> "$TEST_FILE"

if bash docs/ci/check-docs.sh > /dev/null 2>&1; then
  RC=0
else
  RC=$?
fi

if [[ $RC -eq 1 ]]; then
  echo "PASS: S1-sys-shutdown-real-hit (副本注入裸 SYS_SHUTDOWN, 切后模式 exit 1 真抓, 改真生效)"
  exit 0
else
  echo "FAIL: S1-sys-shutdown-real-hit (副本注入裸 SYS_SHUTDOWN, 切后模式未抓, RC=$RC, 改真失效!)" >&2
  exit 1
fi
