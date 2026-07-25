#!/usr/bin/env bash
# =============================================================================
# R66-real-forbidden-hit_negative.sh — 真合规金丝雀 (R66-2 切换后硬判据)
# =============================================================================
# 反例: 在 mktemp 副本中注入一行真禁词 + 合法 marker, check-docs.sh 必须 exit 0
#       副本中 check-docs.sh 切到"读 expanded set"模式 (R66-2 切换后形态).
#       该禁词行应在 expanded set (marker 行精确匹配) → 不被抓.
# 注入: 单行同时含 cosmo_open (真禁词) + D173 marker, marker 覆盖 cosmo_open 行.
# =============================================================================
set -euo pipefail

WORK="${PWD}"
TEST_FILE="docs/01-system-overview.md"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -r "$WORK" "$TMP/repo"
cd "$TMP/repo"

# 注入单行: cosmo_open (真禁词) + D173 marker (合法, 自指)
echo "" >> "$TEST_FILE"
echo "**R66 canary negative**: 注入测试禁词 cosmo_open + D173 marker (单行 marker 覆盖 cosmo_open) <!-- gate-exempt: D173 -->" >> "$TEST_FILE"

# Patch check-docs.sh: AUDIT_LINE_FILTER eval → expanded set 加载 + grep -vFf
PYTHONIOENCODING=utf-8 python3 -c "
import sys
path = 'docs/ci/check-docs.sh'
with open(path, encoding='utf-8') as f:
    src = f.read()
old = '''extract_gate_exempt_markers

for word in \"\${FORBIDDEN[@]}\"; do
  if grep -rnF --exclude=check-docs.sh --exclude=check-d-backlinks.sh --exclude=check_goal_manifest.sh --exclude=check-toolchain.sh --exclude=20-documentation-gate.md --exclude=30-open-questions.md -- \"\$word\" docs/ SPEC.md 2>/dev/null | eval \"\$AUDIT_LINE_FILTER\"; then'''
new = '''extract_gate_exempt_markers
EXPANDED_FILE=\$(mktemp)
bash \"\${PWD}/tools/spec_lab/expand_gate_exempt.sh\" > \"\$EXPANDED_FILE\" 2>/dev/null

for word in \"\${FORBIDDEN[@]}\"; do
  if grep -rnF --exclude=check-docs.sh --exclude=check-d-backlinks.sh --exclude=check_goal_manifest.sh --exclude=check-toolchain.sh --exclude=20-documentation-gate.md --exclude=30-open-questions.md -- \"\$word\" docs/ SPEC.md 2>/dev/null | grep -vFf \"\$EXPANDED_FILE\"; then'''
if old in src and 'EXPANDED_FILE=\$(mktemp)' not in src:
    src = src.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f2:
        f2.write(src)
    print('PATCHED')
else:
    print('SKIP')
" 2>&1 | head -1

if bash docs/ci/check-docs.sh > /dev/null 2>&1; then
  RC=0
else
  RC=$?
fi

if [[ $RC -eq 0 ]]; then
  echo "PASS: R66-real-forbidden-hit_negative (副本注入 cosmo_open + D173 marker, 切后模式 exit 0 正确豁免)"
  exit 0
else
  echo "FAIL: R66-real-forbidden-hit_negative (副本注入 cosmo_open + marker, 切后模式误抓, RC=$RC)" >&2
  exit 1
fi