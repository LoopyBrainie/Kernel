#!/usr/bin/env bash
# =============================================================================
# R64-gate-exempt-count_negative.sh — 反向断言: sidecar 含非零行必被正向抓到 (R64 baseline = 0)
# =============================================================================
# 反例: 在 mktemp 副本内创建一个 sidecar 含 1 行 fake marker →
#   正向断言 (R64 baseline = 0) 必 FAIL → 反向 PASS
# 模仿 R51-M4-ledger-cap_negative.sh 反例: 期待正向断言 RC != 0
# 重要: sidecar 路径用 $PWD 锚定, 允许 positive 在 mktemp 副本内读 mktemp sidecar
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本上, 真 spec 恒不可变
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSITIVE="$LAB_DIR/assertions/R64-gate-exempt-count.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tools/spec_lab/extracted"

# 反例: sidecar 含 1 行 fake marker → R64 baseline 期望 0 → positive 必 FAIL
echo "fake:line:<!-- gate-exempt: D999 -->" > "$WORK/tools/spec_lab/extracted/gate-exempt-markers.txt"

# 跑正向断言 (CWD=副本沙箱)
if ( cd "$WORK" && bash "$POSITIVE" >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

if [[ "$RC" -ne 0 ]]; then
  echo "PASS: R64-gate-exempt-count_negative (反例 count=1 被正向抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R64-gate-exempt-count_negative (反例未被抓, RC=$RC, 正向逻辑失效)" >&2
  exit 1
fi
