#!/usr/bin/env bash
# =============================================================================
# run_negative.sh — 顺跑所有反向断言, 期望全部 FAIL
# =============================================================================
# 这是 "frozen = 编译过的" 的反向防御 — 验证 runner 真能抓烂草图.
# 退出码: 0 = 反例全部被正向抓到 (反向断言全过), 1 = 有反例漏过
# =============================================================================
set -uo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
FAILED_IDS=()

for a in "$LAB_DIR/assertions/"*_negative.sh; do
  base="$(basename "$a")"
  echo "==> $base"
  if bash "$a"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_IDS+=("$base")
  fi
  echo
done

TOTAL=$((PASS + FAIL))
echo "=========================================="
echo "R49 spec_lab negative: $PASS/$TOTAL 反例被抓到"
if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED (反例未被抓到, runner 失效): ${FAILED_IDS[*]}"
  echo "=========================================="
  exit 1
fi
echo "=========================================="
exit 0