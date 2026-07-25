#!/usr/bin/env bash
# =============================================================================
# run_all.sh — R51 收官判据: 顺跑所有正向断言, 期望全过
# =============================================================================
# 退出码: 0 = 全过, 1 = 有断言失败, 2 = 环境错误
# 期望输出: 10/10 PASS (3 R49 + 7 R51 M-bucket)
# =============================================================================
set -uo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
FAILED_IDS=()

# 顺跑所有正向断言 (排除 _negative.sh)
for a in "$LAB_DIR/assertions/"*.sh; do
  base="$(basename "$a")"
  case "$base" in
    *_negative.sh) continue ;;
    audit-rust-unsafe.sh) continue ;;  # 沙箱专用, run_all 默认跳过
  esac
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
echo "R51 spec_lab: $PASS/$TOTAL PASS"
if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED: ${FAILED_IDS[*]}"
  echo "=========================================="
  exit 1
fi
echo "=========================================="
exit 0