#!/usr/bin/env bash
# =============================================================================
# R64-gate-exempt-count.sh — 双阶段 sidecar count 自检 (R64 baseline 0 / R65-γ 推进 ≥ 17)
# =============================================================================
# 抽取源: docs/ci/check-docs.sh § extract_gate_exempt_markers() (R64 D176 立法)
# 输出:   tools/spec_lab/extracted/gate-exempt-markers.txt (gitignored)
# R64 期望: sidecar 存在 + count = 0 (fail-closed skeleton, 0 行为变更)
# R65-γ 期望: count >= 17 (γ(b) 注入 + γ(c)/(d) 累积)
# 设计: 严格判据 (= 0) 在 R65 起失效, 改 OR 逻辑 (count = 0 或 count >= 17)
#       这样:
#         - R64 baseline (count = 0): PASS
#         - R65-γ 推进 (count >= 17): PASS
#         - 中间漂移 (count = 1..16): FAIL (R65-γ 起不应有该区间, 是脏状态)
#         - R65 末态: 严格阶段值由 R65-gate-exempt-count.sh 校 (floor dynamic bump)
# R66 终态: 行为等价切换 (sidecar ⊇ filter 行集 ∧ diff 为空), 集合相等判据
# 验证:
#   1. sidecar 文件存在
#   2. count = 0 (R64 baseline) → PASS
#   3. count >= 17 (R65-γ 推进中) → PASS, 否则 FAIL
# =============================================================================
set -euo pipefail

SIDECAR="$PWD/tools/spec_lab/extracted/gate-exempt-markers.txt"
R65_GAMMA_FLOOR=39  # γ(c-2) 净增 +13 后实测 (26 - 1 撤 + 1 修 + 13 跨文件); γ(c-3/4) 推进时再 bump

# 验证 1: sidecar 存在
if [[ ! -f "$SIDECAR" ]]; then
  echo "FAIL: sidecar 不存在: $SIDECAR" >&2
  echo "      check-docs.sh § extract_gate_exempt_markers() 应在脚本入口写 sidecar" >&2
  exit 1
fi

# 验证 2: 双阶段判据 (count = 0 OR count >= floor)
COUNT=$(awk 'END{print NR+0}' "$SIDECAR")
if [[ "$COUNT" -eq 0 ]]; then
  echo "PASS: R64-gate-exempt-count (sidecar 存在, count = 0, R64 baseline)"
  exit 0
elif [[ "$COUNT" -ge "$R65_GAMMA_FLOOR" ]]; then
  echo "PASS: R64-gate-exempt-count (sidecar 存在, count = $COUNT >= R65-γ floor $R65_GAMMA_FLOOR)"
  exit 0
else
  echo "FAIL: R64-gate-exempt-count (sidecar count = $COUNT, 漂移区间 1..$((R65_GAMMA_FLOOR-1)), 既非 R64 baseline 0 也未达 R65-γ 推进 floor)" >&2
  exit 1
fi
