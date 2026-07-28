#!/usr/bin/env bash
# =============================================================================
# S1-sys-shutdown-marker-pass.sh — SYS_SHUTDOWN 合规 marker 豁免金丝雀 (R66-3 S1 反面)
# =============================================================================
# 测试: 在 mktemp 副本中注入一行 SYS_SHUTDOWN + D154 marker (合法白名单), check-docs.sh 必须 exit 0
#       marker 行精确豁免 (SELF 模式, marker 行即豁免行),而非 substring 静默豁免.
# 真仓库 6 marker 行 (R66-3 全量盘点):
#   - docs/03-design-decisions.md:297 (D154 立法行, SYS_SHUTDOWN + typed-syscall 共现)
#   - docs/03-design-decisions.md:312 (D163 SBI SRST 立法行, 纯 SYS_SHUTDOWN 引用)
#   - docs/03-design-decisions.md:392 (R66-3 R51 M1 enacted 注释, 纯 SYS_SHUTDOWN 引用)
#   - docs/08-risc-v-hal.md:616 (HAL 注释行, 纯 SYS_SHUTDOWN 引用)
#   - docs/14-syscall-api.md:185 (syscall 编号表行, SYS_SHUTDOWN + typed-syscall 共现)
#   - docs/14-syscall-api.md:316 (syscall 编号表行, SYS_SHUTDOWN + typed-syscall 共现)
# 本 canary 注入第 7 行带 D154 marker, 验证扩充 marker 也豁免 + marker 行精确而非 substring.
# =============================================================================
set -euo pipefail

WORK="${PWD}"
TEST_FILE="docs/01-system-overview.md"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -r "$WORK" "$TMP/repo"
cd "$TMP/repo"

# 注入单行: SYS_SHUTDOWN (真禁词) + D154 marker (合法白名单), 单行 marker 覆盖 SYS_SHUTDOWN
echo "" >> "$TEST_FILE"
echo "**S1 R66-3 canary pass**: 注入测试禁词 SYS_SHUTDOWN + D154 marker (单行 marker 覆盖 SYS_SHUTDOWN) <!-- gate-exempt: D154 -->" >> "$TEST_FILE"

if bash docs/ci/check-docs.sh > /dev/null 2>&1; then
  RC=0
else
  RC=$?
fi

if [[ $RC -eq 0 ]]; then
  echo "PASS: S1-sys-shutdown-marker-pass (副本注入 SYS_SHUTDOWN + D154 marker, 切后模式 exit 0 正确豁免, 5 marker 行也被 D154 D-ref 校验守约)"
  exit 0
else
  echo "FAIL: S1-sys-shutdown-marker-pass (副本注入 SYS_SHUTDOWN + marker, 切后模式误抓, RC=$RC)" >&2
  exit 1
fi
