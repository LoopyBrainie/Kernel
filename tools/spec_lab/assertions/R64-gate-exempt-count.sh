#!/usr/bin/env bash
# =============================================================================
# R64-gate-exempt-count.sh — 正向断言: gate-exempt marker sidecar 存在 + R64 baseline (0 行)
# =============================================================================
# 抽取源: docs/ci/check-docs.sh § extract_gate_exempt_markers() (R64 D176 立法)
# 输出:   tools/spec_lab/extracted/gate-exempt-markers.txt (gitignored, clean clone 首跑必创建)
# R64 期望: sidecar 存在 + count = 0 (fail-closed skeleton, 0 行为变更; 主门禁不读 marker)
# R65+ 升级: 新建 R65-gate-exempt-count.sh, 期望 count ≥ 50 (50 行 marker 注入 + 30 文件级展开)
# R66 末态: 期望 count ≥ 50 (行为等价切换不丢覆盖)
# 验证:
#   1. sidecar 文件存在 (extract_gate_exempt_markers 已注入 check-docs.sh 入口调用)
#   2. R64 baseline — count = 0 (空集合通过 fail-closed; 多出 marker 视为漂移)
# 路径解析:
#   - $PWD 锚定 CWD, 允许 mktemp 副本内跑 (run_negative.sh 模式)
#   - 真 repo 跑时 $PWD = repo root, $SIDECAR = repo/tools/spec_lab/extracted/gate-exempt-markers.txt
# 失败模式: sidecar 缺失 (extract 未跑) / count ≠ 0 (R64 不应有 marker)
# =============================================================================
set -euo pipefail

SIDECAR="$PWD/tools/spec_lab/extracted/gate-exempt-markers.txt"

# 验证 1: sidecar 存在
if [[ ! -f "$SIDECAR" ]]; then
  echo "FAIL: sidecar 不存在: $SIDECAR" >&2
  echo "      check-docs.sh § extract_gate_exempt_markers() 应在脚本入口写 sidecar" >&2
  echo "      (clean clone 必挂路径: 干净克隆首跑若缺 sidecar, 须先调本断言的 'bash docs/ci/check-docs.sh' 触发 mkdir -p + 抽取)" >&2
  exit 1
fi

# 验证 2: R64 baseline = 0 行
COUNT=$(awk 'END{print NR+0}' "$SIDECAR")
if [[ "$COUNT" -ne 0 ]]; then
  echo "FAIL: R64 期望 sidecar count = 0 (fail-closed skeleton, 0 行为变更), 实测 $COUNT" >&2
  echo "      R64 不应有 marker; R65+ 升级为 R65-gate-exempt-count.sh 期望 ≥ 50" >&2
  exit 1
fi

echo "PASS: R64-gate-exempt-count (sidecar 存在, count = 0, D176 §1.3 R64 立法骨架状态)"
exit 0
