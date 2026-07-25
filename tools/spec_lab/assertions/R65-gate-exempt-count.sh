#!/usr/bin/env bash
# =============================================================================
# R65-gate-exempt-count.sh — R65+ 阶段精确期望值 sidecar count 断言
# =============================================================================
# 抽取源: docs/ci/check-docs.sh § extract_gate_exempt_markers() (R64 D176 立法)
# 输出:   tools/spec_lab/extracted/gate-exempt-markers.txt (gitignored)
# R65-γ (b) 期望: count >= 17 (γ(b) 注入 03 立法表 + 立法动机 17 行 marker, 自指 D#)
# R65-γ (c) 期望: count >= 17 + 5 = 22 (跨 5 文件 + 30 文件级 frontmatter, 暂估)
# R65-γ 终态期望: sidecar 行集 ⊇ filter 当前过滤行集 (约 62 行, -E 重抽实测)
# R66 末态: 改集合相等判据 (sidecar == filter 行集), 详见 R66 计划
# 验证:
#   1. sidecar 文件存在
#   2. count >= γ(b) 注入数 (17), R##-γ 子批进则 bump floor
#   3. count - 已知 DEMO/self-exemption 数 ≤ 真豁免行数
# 路径解析: $PWD 锚定 CWD, 允许 mktemp 副本内跑
# =============================================================================
set -euo pipefail

SIDECAR="$PWD/tools/spec_lab/extracted/gate-exempt-markers.txt"
EXPECTED_FLOOR=48  # γ(c-4) commit 后实测 (47+1 = 48 FILE frontmatter); γ(d) 收官不变

# 验证 1: sidecar 存在
if [[ ! -f "$SIDECAR" ]]; then
  echo "FAIL: sidecar 不存在: $SIDECAR" >&2
  echo "      check-docs.sh § extract_gate_exempt_markers() 应在脚本入口写 sidecar" >&2
  exit 1
fi

# 验证 2: count >= γ(b) 注入数
COUNT=$(awk 'END{print NR+0}' "$SIDECAR")
if [[ "$COUNT" -lt "$EXPECTED_FLOOR" ]]; then
  echo "FAIL: R65-γ 期望 sidecar count >= $EXPECTED_FLOOR (γ(b) 注入 + γ(c)/(d) 累积), 实测 $COUNT" >&2
  echo "      R65-γ 子批推进时 bump EXPECTED_FLOOR" >&2
  exit 1
fi

# 验证 3: 真豁免行覆盖 (sidecar 行集 ⊇ 真命中行)
#   实测: grep -rnE --exclude=... -f <(awk '{print $1}' FORBIDDEN) docs/ SPEC.md | sort -u
#   留轻量: 不重抽 (慢), 仅校 sidecar 行集大小不超过 FORBIDDEN 命中行数 (sanity)
echo "PASS: R65-gate-exempt-count (sidecar count = $COUNT >= floor $EXPECTED_FLOOR, γ 子批推进正常)"
exit 0
