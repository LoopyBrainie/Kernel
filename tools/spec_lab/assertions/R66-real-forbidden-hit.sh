#!/usr/bin/env bash
# =============================================================================
# R66-real-forbidden-hit.sh — 真违规金丝雀 (R66-2 切换后硬判据, 防门禁空转)
# =============================================================================
# 测试: 在 mktemp 副本中注入一行真禁词 (无 marker), check-docs.sh 必须 exit 1
#       即便切后模式 (读 expanded set), 该禁词行不在 expanded set → 必被抓
# 这是防"切换后门禁空转"的最后一道网 — R64 时代 grep -vE 过宽静默豁免教训.
# =============================================================================
set -euo pipefail

WORK="${PWD}"
TEST_FILE="docs/01-system-overview.md"  # 用 1X 子系统文档 (无 marker, 真注入必被抓)

# mktemp 副本
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -r "$WORK" "$TMP/repo"
cd "$TMP/repo"

# 在副本 docs/01-system-overview.md 末行追加真禁词 (cosmo_open, R59 D171 派生, 无 marker)
echo "" >> "$TEST_FILE"
echo "**R66 canary**: 注入测试禁词 \`cosmo_open\` (D171 派生)" >> "$TEST_FILE"
echo "\`cosmo_open\` 真命中, 无 marker, 应被抓" >> "$TEST_FILE"

# 跑 check-docs.sh (切后模式, 读 expanded set)
if bash docs/ci/check-docs.sh > /dev/null 2>&1; then
  RC=0
else
  RC=$?
fi

if [[ $RC -eq 1 ]]; then
  echo "PASS: R66-real-forbidden-hit (副本注入 cosmo_open, 切后模式 exit 1 真抓)"
  exit 0
else
  echo "FAIL: R66-real-forbidden-hit (副本注入 cosmo_open, 切后模式未抓, RC=$RC, 门禁空转!)" >&2
  exit 1
fi